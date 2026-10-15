"""ADB integration checks: real alarm delivery after process death/Doze and reboot restoration."""
import json
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from device_preferences import read_runtime

PACKAGE = 'com.niceday.memo.stable'
RECEIVER = f'{PACKAGE}/com.niceday.memo.DebugAlarmProbe'
def adb(*args, check=True):
    result = subprocess.run(['adb', *args], check=False, capture_output=True, text=True, timeout=45)
    if check and result.returncode:
        print(f"ADB command {args!r} failed: {result.stderr.strip()} {result.stdout.strip()}", flush=True)
        raise subprocess.CalledProcessError(result.returncode, result.args, output=result.stdout, stderr=result.stderr)
    return result.stdout.strip()
def shell(*args, check=True):
    return adb('shell', *args, check=check)
def runtime():
    return read_runtime(adb, PACKAGE)

def device_clock():
    return {'epoch_ms': int(shell('date', '+%s')) * 1000,
            'elapsed_ms': int(float(shell('cat', '/proc/uptime').split()[0]) * 1000)}
def seed(seconds):
    shell('am', 'broadcast', '--receiver-foreground', '-n', RECEIVER, '-a', 'SEED', '--ei', 'seconds', str(seconds))
    value = runtime()
    rows = json.loads(value['reminders'])
    return rows[-1]['id'], rows[-1]['nextTrigger']

subprocess.run(['adb', 'install', '-r', 'build/app/outputs/flutter-apk/app-debug.apk'], check=True)
shell('pm', 'grant', PACKAGE, 'android.permission.POST_NOTIFICATIONS')
# Cold emulators may receive an asynchronous network clock correction after boot.
# Freeze automatic correction for this elapsed delivery experiment; keep the 15 s limit.
shell('settings', 'put', 'global', 'auto_time', '0')
shell('settings', 'put', 'global', 'auto_time_zone', '0')
assert shell('settings', 'get', 'global', 'auto_time') == '0'
time.sleep(10)
shell('am', 'start', '-n', f'{PACKAGE}/com.niceday.memo.MainActivity')
# Cold Flutter startup and boot broadcasts may still be queued after am start returns.
# Wait for the UI's real native bootstrap before sending fixture broadcasts.
startup_deadline = time.monotonic() + 90
startup_ready = False
while time.monotonic() < startup_deadline:
    try:
        startup_ready = any(e['type'] == 'restored' and e['detail'] == '恢复排程'
                            for e in json.loads(runtime().get('trace', '[]')))
        if startup_ready:
            break
    except (subprocess.SubprocessError, ET.ParseError, KeyError, ValueError):
        pass
    time.sleep(1)
assert startup_ready, 'Cold application startup did not reach native bootstrap'
shell('input', 'keyevent', 'KEYCODE_HOME')
shell('am', 'broadcast', '--receiver-foreground', '-n', RECEIVER, '-a', 'CLEAR')
shell('am', 'broadcast', '--receiver-foreground', '-n', RECEIVER, '-a', 'CORE_MODE')
clock_before = device_clock()
id, planned = seed(25)
print('Scheduled diagnostic:', json.dumps({'planned': planned, 'clock': clock_before,
    'trace': json.loads(runtime()['trace'])}, ensure_ascii=False), flush=True)
start_pid = shell('pidof', PACKAGE)
shell('input', 'keyevent', 'KEYCODE_HOME')
assert runtime().get('reliableMode') == 'false', 'Core test must disable the guardian'
# am kill can skip a process still temporarily important after an ordered probe broadcast.
# Terminate only this debug UID, without placing the package in force-stopped state.
shell('am', 'broadcast', '--receiver-foreground', '-n', RECEIVER, '-a', 'KILL_PROCESS')
time.sleep(2)
assert not shell('pidof', PACKAGE, check=False), 'Target process did not terminate'
shell('input', 'keyevent', 'KEYCODE_SLEEP')
shell('dumpsys', 'battery', 'unplug')
shell('dumpsys', 'deviceidle', 'force-idle')
try:
    fired = None
    host_started = time.monotonic()
    host_deadline = host_started + 180
    while time.monotonic() < host_deadline:
        time.sleep(1)
        observed = runtime()
        rows = json.loads(observed['reminders'])
        fired = next(r for r in rows if r['id'] == id)
        # The engine commits the attempt before calling NotificationManager.
        # Wait for the completed notify call, not that intermediate storage state.
        observed_trace = json.loads(observed.get('trace', '[]'))
        if fired.get('attempts', 0) == 1 and any(e['id'] == id and e['type'] == 'notified' for e in observed_trace):
            break
        # Guest wall time defines the alarm deadline. A slow virtual device must not
        # be declared late solely because 40 host seconds elapsed.
        if int(shell('date', '+%s')) * 1000 > planned + 16000:
            break
    value = runtime()
    trace = json.loads(value['trace'])
    alarm_diagnostic = {'planned': planned, 'clock_before': clock_before,
        'clock_after': device_clock(), 'reminder': fired, 'trace': trace,
        'lastError': value.get('lastError'), 'auto_time_disabled': True,
        'host_poll_elapsed_ms': int((time.monotonic() - host_started) * 1000)}
    print('Alarm diagnostic:', json.dumps(alarm_diagnostic, ensure_ascii=False), flush=True)
    Path(f'device-alarm-test-results-api{shell("getprop", "ro.build.version.sdk")}.json').write_text(json.dumps({'process_death_doze': False,
        'reboot_restore_without_activity': False, 'alarm_diagnostic': alarm_diagnostic}, indent=2))
    received_events = [e for e in trace if e['id'] == id and e['type'] == 'received']
    if not fired or fired.get('attempts') != 1 or not received_events or received_events[-1]['at'] - planned >= 15000:
        print('System alarm dump:', shell('dumpsys', 'alarm'), flush=True)
        log = shell('logcat', '-d', '-t', '1500', check=False)
        print('\n'.join(line for line in log.splitlines() if any(term in line for term in
            ['niceday', 'FATAL EXCEPTION', 'AlarmManager', 'TimeDetector', 'time_detector', 'TIME_SET', 'Reminder'])), flush=True)
    assert fired and fired.get('attempts') == 1, 'Alarm did not fire with UI absent/process killed'
    received = next(e for e in reversed(trace) if e['id'] == id and e['type'] == 'received')
    assert str(received['pid']) != start_pid, 'Receiver did not restart in a new process'
    assert received['at'] >= planned, 'Alarm fired early'
    assert received['at'] - planned < 15000, 'Alarm delivery was delayed excessively'
    delivery_delay_ms = received['at'] - planned
    posted = [e for e in trace if e['id'] == id and e['type'] == 'notified']
    assert posted, 'Notification was not posted'
    assert 0 <= posted[-1]['at'] - planned < 15000, 'Notification posting missed the delivery deadline'
    print('PASS: system alarm delivered in background after process kill and forced Doze', flush=True)
finally:
    shell('dumpsys', 'deviceidle', 'unforce', check=False)
    shell('dumpsys', 'battery', 'reset', check=False)

shell('input', 'keyevent', 'KEYCODE_WAKEUP')
shell('wm', 'dismiss-keyguard', check=False)
shell('am', 'broadcast', '--receiver-foreground', '-n', RECEIVER, '-a', 'CLEAR')
id, planned = seed(240)
before_trace = json.loads(runtime()['trace'])
before_count = len(before_trace)
adb('reboot')
adb('wait-for-device')
for _ in range(90):
    if shell('getprop', 'sys.boot_completed') == '1': break
    time.sleep(1)
# sys.boot_completed is set before all queued app broadcasts are delivered.
# Compare newly appended device events, not host vs guest wall clocks.
restored = False
value = {}
trace = []
for attempt in range(100):
    try:
        value = runtime()
        trace = json.loads(value.get('trace', '[]'))
        fresh = trace[before_count:] if len(trace) >= before_count else trace
        # Wait for credential-unlocked boot too; LOCKED_BOOT_COMPLETED alone is
        # insufficient readiness for the following secure-lockscreen UI checks.
        restored = any(e['type'] == 'restored' and e['detail'] == 'android.intent.action.BOOT_COMPLETED' for e in fresh)
        scheduled = any(e['type'] == 'scheduled' and e['id'] == id for e in fresh)
        if restored and scheduled: break
    except Exception:
        pass
    if attempt == 45:
        shell('input', 'keyevent', 'KEYCODE_WAKEUP')
        shell('wm', 'dismiss-keyguard', check=False)
    time.sleep(1)
print('Boot diagnostic:', json.dumps({'trace': trace, 'lastError': value.get('lastError'),
    'before_count': before_count, 'restored': restored}, ensure_ascii=False), flush=True)
if not restored:
    print(shell('dumpsys', 'package', PACKAGE), flush=True)
    log = shell('logcat', '-d', '-t', '500', check=False)
    print('\n'.join(line for line in log.splitlines() if 'niceday' in line or 'FATAL EXCEPTION' in line or 'Reminder' in line), flush=True)
assert restored, 'Boot receiver did not restore'
assert any(e['type'] == 'scheduled' and e['id'] == id for e in fresh), 'Alarm was not re-registered after boot'
assert PACKAGE in shell('dumpsys', 'alarm'), 'System has no alarm registration after boot'
print('PASS: reboot restored scheduled reminder without opening Flutter Activity', flush=True)
Path(f'device-alarm-test-results-api{shell("getprop", "ro.build.version.sdk")}.json').write_text(json.dumps({'process_death_doze': True,
    'reboot_restore_without_activity': True, 'alarm_delivery_delay_ms': delivery_delay_ms,
    'alarm_diagnostic': alarm_diagnostic}, indent=2))
