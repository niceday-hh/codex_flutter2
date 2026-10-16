"""Real unlocked overlay, unread timeout, explicit acknowledgement and screen-off removal."""
import json
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from device_preferences import read_runtime, await_created

PACKAGE = 'com.niceday.memo.stable'
RECEIVER = f'{PACKAGE}/com.niceday.memo.DebugAlarmProbe'
RESULT = None

def adb(*args, check=True):
    p = subprocess.run(['adb', *args], capture_output=True, text=True, timeout=45)
    if check and p.returncode:
        raise RuntimeError(f'ADB {args}: {p.stderr} {p.stdout}')
    return p.stdout.strip()

def shell(*args, check=True):
    return adb('shell', *args, check=check)

def probe(action, *extra):
    return shell('am', 'broadcast', '--receiver-foreground', '-n', RECEIVER, '-a', action, *extra)

def runtime():
    return read_runtime(adb, PACKAGE)

def row(id):
    return next(r for r in json.loads(runtime()['reminders']) if r['id'] == id)

def windows():
    return shell('dumpsys', 'window', 'windows')

def wait(predicate, message, timeout=75):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.25)
    raise AssertionError(message)

def seed():
    return await_created(probe('BANNER_SEED', '--ei', 'seconds', '15'), runtime)['id']

def shown(id):
    return any(e['type'] == 'popup_shown' and e['id'] == id for e in json.loads(runtime().get('trace', '[]')))

result = {'overlay_unlocked': False, 'timeout_keeps_unread': False,
          'explicit_read_cancels_retry': False, 'screen_off_removes_card': False,
          'permission_denial_preserves_notification': False}
RESULT = Path(f'device-popup-test-results-api{shell("getprop", "ro.build.version.sdk")}.json')
try:
    shell('input', 'keyevent', 'KEYCODE_WAKEUP')
    shell('wm', 'dismiss-keyguard', check=False)
    shell('input', 'keyevent', 'KEYCODE_HOME')
    probe('CLEAR'); probe('CORE_MODE')
    shell('appops', 'set', PACKAGE, 'SYSTEM_ALERT_WINDOW', 'allow')
    probe('POPUP_MODE', '--ez', 'enabled', 'true')
    id = seed()
    wait(lambda: shown(id), 'No overlay after unlocked background alarm')
    assert 'MemoReminderPopup' in windows(), 'No actual WindowManager overlay'
    result['overlay_unlocked'] = True
    wait(lambda: 'MemoReminderPopup' not in windows(), 'Card did not time out', 20)
    assert not row(id).get('acknowledged') and row(id).get('retryAt', 0) > 0, row(id)
    result['timeout_keeps_unread'] = True
    probe('CLEAR')
    id = seed()
    wait(lambda: shown(id), 'Second overlay not shown')
    # The card deliberately does not take focus: query all interactive windows.
    shell('uiautomator', 'dump', '--windows', '/sdcard/popup-window.xml')
    xml = shell('cat', '/sdcard/popup-window.xml')
    root = ET.fromstring(xml)
    nodes = [n for n in root.iter('node') if n.attrib.get('text') == '已读']
    assert nodes and '后台提醒自检' in xml and '亮屏提醒卡片' in xml, xml
    import re
    coords = list(map(int, re.findall(r'\d+', nodes[0].attrib['bounds'])))
    shell('input', 'tap', str((coords[0] + coords[2]) // 2), str((coords[1] + coords[3]) // 2))
    wait(lambda: row(id).get('acknowledged'), 'Read button did not acknowledge', 8)
    assert row(id).get('retryAt', 0) == 0
    result['explicit_read_cancels_retry'] = True
    probe('CLEAR')
    id = seed()
    wait(lambda: shown(id), 'Third overlay not shown')
    shell('input', 'keyevent', 'KEYCODE_SLEEP')
    wait(lambda: 'MemoReminderPopup' not in windows(), 'Card remained after screen off', 5)
    assert not row(id).get('acknowledged'), row(id)
    result['screen_off_removes_card'] = True
    probe('CLEAR')
    shell('input', 'keyevent', 'KEYCODE_WAKEUP')
    shell('wm', 'dismiss-keyguard', check=False)
    shell('input', 'keyevent', 'KEYCODE_HOME')
    shell('appops', 'set', PACKAGE, 'SYSTEM_ALERT_WINDOW', 'deny')
    id = seed()
    wait(lambda: row(id).get('attempts') == 1, 'Notification not delivered without overlay permission')
    wait(lambda: any(e['type'] == 'notified' and e['id'] == id for e in json.loads(runtime().get('trace', '[]'))), 'Notification not posted')
    assert not shown(id) and 'MemoReminderPopup' not in windows()
    probe('SNAPSHOT')
    posted = json.loads(adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/notification-probe.json'))
    assert any(n['id'] == id and not n['fullscreen'] for n in posted), posted
    result['permission_denial_preserves_notification'] = True
    print('Unlocked overlay device checks passed:', result, flush=True)
finally:
    RESULT.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    probe('POPUP_MODE', '--ez', 'enabled', 'false')
    probe('CLEAR')
    shell('appops', 'set', PACKAGE, 'SYSTEM_ALERT_WINDOW', 'default', check=False)
