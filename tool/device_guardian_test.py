"""Real task removal, SIGKILL/sticky recovery, reboot delivery and force-stop boundary.
Debug-only fixture broadcasts prepare data; none simulate a BASE/RETRY delivery.
"""
import json
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from device_preferences import read_runtime

PACKAGE = 'com.niceday.memo.stable'
RECEIVER = f'{PACKAGE}/com.niceday.memo.DebugAlarmProbe'
ACTIVITY = f'{PACKAGE}/com.niceday.memo.MainActivity'


def adb(*args, check=True):
    result = subprocess.run(['adb', *args], check=False, capture_output=True, text=True, timeout=45)
    if check and result.returncode:
        print(f"ADB command {args!r} failed: {result.stderr.strip()} {result.stdout.strip()}", flush=True)
        raise subprocess.CalledProcessError(result.returncode, result.args, output=result.stdout, stderr=result.stderr)
    return result.stdout.strip()


def shell(*args, check=True):
    return adb('shell', *args, check=check)


def broadcast(action, *extras):
    return shell('am', 'broadcast', '--receiver-foreground', '-n', RECEIVER, '-a', action, *extras)


def runtime():
    return read_runtime(adb, PACKAGE)

def events():
    return json.loads(runtime().get('trace', '[]'))


def wait_for(predicate, timeout, message):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except (subprocess.SubprocessError, ET.ParseError, KeyError, ValueError):
            pass
        time.sleep(1)
    raise AssertionError(message)


def seed(seconds):
    broadcast('SEED', '--ei', 'seconds', str(seconds))
    r = json.loads(runtime()['reminders'])[-1]
    return r['id'], r['nextTrigger']


def delivered(id, planned):
    def fired():
        value = runtime()
        row = next(r for r in json.loads(value['reminders']) if r['id'] == id)
        trace = json.loads(value.get('trace', '[]'))
        notified = [e for e in trace if e['type'] == 'notified' and e['id'] == id]
        if row.get('attempts') == 1 and notified:
            return {'row': row, 'notified': notified[-1], 'trace': trace, 'lastError': value.get('lastError', '')}
        assert int(shell('date', '+%s')) * 1000 <= planned + 16000, 'Alarm missed its guest-clock deadline'
        return None
    value = wait_for(fired, 360, f'Reminder {id} did not actually fire')
    delay = value['row']['lastFired'] - planned
    assert 0 <= delay < 15000, f'Alarm delivery delay {delay} ms'
    return {'delivery_delay_ms': delay, **value}


sdk = shell('getprop', 'ro.build.version.sdk')
result_path = Path(f'device-guardian-test-results-api{sdk}.json')
result = {'sdk': int(sdk), 'task_removal': False, 'sticky_process_recovery': False,
          'reboot_actual_delivery_without_activity': False, 'force_stop_boundary': False,
          'physical_honor_tested': False}
result_path.write_text(json.dumps(result, indent=2))
try:
    shell('input', 'keyevent', 'KEYCODE_WAKEUP')
    shell('wm', 'dismiss-keyguard', check=False)
    broadcast('CLEAR')
    shell('am', 'start', '-n', ACTIVITY)
    time.sleep(3)
    broadcast('GUARDIAN_MODE')
    id, planned = seed(120)
    wait_for(lambda: any(e['type'] == 'guardian_started' for e in events()), 20, 'Foreground service did not start')
    service_dump = shell('dumpsys', 'activity', 'services', PACKAGE)
    assert 'ReminderGuardianService' in service_dump and 'isForeground=true' in service_dump, service_dump
    result['foreground_service_observed'] = True
    shell('input', 'keyevent', 'KEYCODE_HOME')
    broadcast('REMOVE_TASK')
    wait_for(lambda: any(e['type'] == 'task_removed' for e in events()), 20, 'Real task removal did not reach the service')
    result['task_removal'] = True
    old_pid = shell('pidof', PACKAGE)
    assert old_pid and ' ' not in old_pid, old_pid
    # am kill skips foreground services. SIGKILL targets only our debug application's UID.
    broadcast('KILL_PROCESS')
    def recovered():
        pid = shell('pidof', PACKAGE, check=False)
        restarted = [e for e in events() if e['type'] == 'guardian_started' and str(e['pid']) != old_pid]
        if pid and pid != old_pid and restarted:
            assert restarted[-1]['at'] < planned, 'Recovery only happened because the alarm fired'
            assert restarted[-1]['detail'] == '系统恢复服务', 'Service was not recreated by Android with a null intent'
            return {'old_pid': old_pid, 'new_pid': pid, 'event': restarted[-1]}
        return None
    result['sticky_recovery'] = wait_for(recovered, 90, 'Android did not recreate the sticky service before the alarm')
    result['sticky_process_recovery'] = True
    result['process_recovery_delivery'] = delivered(id, planned)
    print('PASS: real task removal, SIGKILL, OS sticky service recreation and actual alarm delivery', flush=True)

    broadcast('CLEAR')
    id, planned = seed(180)
    before = max(e['at'] for e in events())
    adb('reboot')
    adb('wait-for-device')
    wait_for(lambda: shell('getprop', 'sys.boot_completed') == '1', 120, 'Device reboot did not complete')
    def boot_restored():
        fresh = [e for e in events() if e['at'] > before]
        return (any(e['type'] == 'restored' and e['detail'] == 'android.intent.action.BOOT_COMPLETED' for e in fresh)
                and any(e['type'] == 'scheduled' and e['id'] == id for e in fresh)
                and any(e['type'] == 'guardian_started' for e in fresh))
    wait_for(boot_restored, 100, 'Boot receiver/service did not restore without Activity')
    result['reboot_delivery'] = delivered(id, planned)
    result['reboot_actual_delivery_without_activity'] = True
    print('PASS: reboot restored service and actually delivered the alarm without opening the Activity', flush=True)

    broadcast('CLEAR')
    id, planned = seed(20)
    shell('am', 'force-stop', PACKAGE)
    wait_for(lambda: int(shell('date', '+%s')) * 1000 > planned + 5000, 75, 'Guest clock failed to advance')
    value = runtime()
    row = next(r for r in json.loads(value['reminders']) if r['id'] == id)
    assert not shell('pidof', PACKAGE, check=False), 'Force-stopped app unexpectedly restarted itself'
    assert row.get('attempts', 0) == 0, 'Force-stop did not block the alarm as documented'
    shell('am', 'start', '-n', ACTIVITY)
    wait_for(lambda: next(r for r in json.loads(runtime()['reminders']) if r['id'] == id).get('attempts') == 1,
             30, 'Explicit user launch did not restore the missed reminder')
    result['force_stop_boundary'] = True
    print('PASS: force-stop remains a system boundary; explicit relaunch restores the missed task', flush=True)
finally:
    if not all(result[k] for k in ['task_removal', 'sticky_process_recovery', 'reboot_actual_delivery_without_activity', 'force_stop_boundary']):
        try:
            print('Guardian failure:', json.dumps({'result': result, 'runtime': runtime()}, ensure_ascii=False), flush=True)
            print(shell('dumpsys', 'activity', 'services', PACKAGE), flush=True)
            log = shell('logcat', '-d', '-t', '1200', check=False)
            print('\n'.join(line for line in log.splitlines() if any(s in line for s in ['niceday', 'FATAL EXCEPTION', 'ForegroundService', 'Reminder'])), flush=True)
        except Exception as error:
            print('Could not capture guardian diagnostic:', str(error), flush=True)
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2))
