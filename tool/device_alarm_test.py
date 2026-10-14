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
def seed(seconds):
    shell('am', 'broadcast', '-n', RECEIVER, '-a', 'SEED', '--ei', 'seconds', str(seconds))
    value = runtime()
    rows = json.loads(value['reminders'])
    return rows[-1]['id'], rows[-1]['nextTrigger']

subprocess.run(['adb', 'install', '-r', 'build/app/outputs/flutter-apk/app-debug.apk'], check=True)
shell('pm', 'grant', PACKAGE, 'android.permission.POST_NOTIFICATIONS')
shell('am', 'start', '-n', f'{PACKAGE}/com.niceday.memo.MainActivity')
time.sleep(3)
shell('input', 'keyevent', 'KEYCODE_HOME')
shell('am', 'broadcast', '-n', RECEIVER, '-a', 'CLEAR')
id, planned = seed(25)
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
    assert fired and fired.get('attempts') == 1, 'Alarm did not fire with UI absent/process killed'
    trace = json.loads(runtime()['trace'])
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
before = int(time.time() * 1000)
adb('reboot')
adb('wait-for-device')
for _ in range(90):
    if shell('getprop', 'sys.boot_completed') == '1': break
    time.sleep(1)
time.sleep(5)
try:
    trace = json.loads(runtime()['trace'])
except Exception:
    shell('input', 'keyevent', 'KEYCODE_WAKEUP'); shell('wm', 'dismiss-keyguard', check=False)
    time.sleep(5); trace = json.loads(runtime()['trace'])
assert any(e['type'] == 'restored' and e['at'] >= before and 'BOOT_COMPLETED' in e['detail'] for e in trace), 'Boot receiver did not restore'
assert any(e['type'] == 'scheduled' and e['id'] == id and e['at'] >= before for e in trace), 'Alarm was not re-registered after boot'
assert PACKAGE in shell('dumpsys', 'alarm'), 'System has no alarm registration after boot'
print('PASS: reboot restored scheduled reminder without opening Flutter Activity', flush=True)
Path('device-test-results.json').write_text(json.dumps({'process_death_doze': True, 'reboot_restore_without_activity': True}, indent=2))
