"""ADB integration checks: real alarm delivery after process death/Doze and reboot restoration."""
import json
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = 'com.niceday.memo.stable'
RECEIVER = f'{PACKAGE}/com.niceday.memo.DebugAlarmProbe'
def adb(*args, check=True):
    return subprocess.run(['adb', *args], check=check, capture_output=True, text=True).stdout.strip()
def shell(*args, check=True):
    return adb('shell', *args, check=check)
def runtime():
    xml = adb('exec-out', 'run-as', PACKAGE, 'cat', f'/data/user_de/0/{PACKAGE}/shared_prefs/memo-runtime.xml')
    tree = ET.fromstring(xml)
    return {e.attrib['name']: e.text if e.tag == 'string' else e.attrib.get('value') for e in tree}
def device_clock():
    return {'epoch_ms': int(shell('date', '+%s')) * 1000,
            'elapsed_ms': int(float(shell('cat', '/proc/uptime').split()[0]) * 1000)}
def seed(seconds):
    shell('am', 'broadcast', '-n', RECEIVER, '-a', 'SEED', '--ei', 'seconds', str(seconds))
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
time.sleep(3)
shell('input', 'keyevent', 'KEYCODE_HOME')
shell('am', 'broadcast', '-n', RECEIVER, '-a', 'CLEAR')
clock_before = device_clock()
id, planned = seed(25)
print('Scheduled diagnostic:', json.dumps({'planned': planned, 'clock': clock_before,
    'trace': json.loads(runtime()['trace'])}, ensure_ascii=False), flush=True)
start_pid = shell('pidof', PACKAGE)
shell('input', 'keyevent', 'KEYCODE_HOME')
shell('am', 'kill', PACKAGE)
time.sleep(2)
assert not shell('pidof', PACKAGE, check=False), 'Target process did not terminate'
shell('input', 'keyevent', 'KEYCODE_SLEEP')
shell('dumpsys', 'battery', 'unplug')
shell('dumpsys', 'deviceidle', 'force-idle')
try:
    fired = None
    for _ in range(40):
        time.sleep(1)
        rows = json.loads(runtime()['reminders'])
        fired = next(r for r in rows if r['id'] == id)
        if fired.get('attempts', 0) == 1:
            break
    value = runtime()
    trace = json.loads(value['trace'])
    alarm_diagnostic = {'planned': planned, 'clock_before': clock_before,
        'clock_after': device_clock(), 'reminder': fired, 'trace': trace,
        'lastError': value.get('lastError'), 'auto_time_disabled': True}
    print('Alarm diagnostic:', json.dumps(alarm_diagnostic, ensure_ascii=False), flush=True)
    Path('device-test-results.json').write_text(json.dumps({'process_death_doze': False,
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
    assert any(e['id'] == id and e['type'] == 'notified' for e in trace), 'Notification was not posted'
    print('PASS: system alarm delivered in background after process kill and forced Doze', flush=True)
finally:
    shell('dumpsys', 'deviceidle', 'unforce', check=False)
    shell('dumpsys', 'battery', 'reset', check=False)

shell('input', 'keyevent', 'KEYCODE_WAKEUP')
shell('wm', 'dismiss-keyguard', check=False)
shell('am', 'broadcast', '-n', RECEIVER, '-a', 'CLEAR')
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
        restored = any(e['type'] == 'restored' and 'BOOT_COMPLETED' in e['detail'] for e in fresh)
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
Path('device-test-results.json').write_text(json.dumps({'process_death_doze': True,
    'reboot_restore_without_activity': True, 'alarm_delivery_delay_ms': received['at'] - planned,
    'alarm_diagnostic': alarm_diagnostic}, indent=2))
