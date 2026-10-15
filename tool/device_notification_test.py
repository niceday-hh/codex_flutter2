"""Real SystemUI privacy transition after the app process is gone; no physical vibration claim."""
import json
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = 'com.niceday.memo.stable'
RECEIVER = f'{PACKAGE}/com.niceday.memo.DebugAlarmProbe'
BODY = '后台提醒自检'
PIN = '1357'
RESULT = Path('notification-device-test-results.json')


def adb(*args, check=True):
    return subprocess.run(['adb', *args], check=check, capture_output=True, text=True, timeout=45).stdout.strip()


def shell(*args, check=True):
    return adb('shell', *args, check=check)


def broadcast(action):
    return shell('am', 'broadcast', '-n', RECEIVER, '-a', action)


def rows():
    source = adb('exec-out', 'run-as', PACKAGE, 'cat', f'/data/user_de/0/{PACKAGE}/shared_prefs/memo-runtime.xml')
    root = ET.fromstring(source)
    return json.loads(next(e.text for e in root if e.attrib.get('name') == 'reminders'))


def ui():
    shell('uiautomator', 'dump', '/sdcard/notification-window.xml')
    return shell('cat', '/sdcard/notification-window.xml')


def wait_ui(body_visible, timeout=30):
    deadline = time.monotonic() + timeout
    latest = ''
    while time.monotonic() < deadline:
        shell('cmd', 'statusbar', 'expand-notifications', check=False)
        latest = ui()
        if (BODY in latest if body_visible else BODY not in latest and '解锁后查看' in latest):
            return latest
        time.sleep(1)
    raise AssertionError(f'SystemUI privacy mismatch (body_visible={body_visible}): {latest}')


original = {key: shell('settings', 'get', 'secure', key) for key in
            ['lock_screen_show_notifications', 'lock_screen_allow_private_notifications',
             'lock_screen_lock_after_timeout', 'lockscreen.power_button_instantly_locks']}
timeout_before = shell('settings', 'get', 'system', 'screen_off_timeout')
result = {'lock_unlock_relock_without_app_process': False, 'channel_three_pulse_pattern': False,
          'physical_vibration_verified': False}
RESULT.write_text(json.dumps(result, indent=2))
pin_set = False
try:
    shell('input', 'keyevent', 'KEYCODE_WAKEUP')
    shell('wm', 'dismiss-keyguard', check=False)
    broadcast('CLEAR')
    for key, value in [('lock_screen_show_notifications', '1'), ('lock_screen_allow_private_notifications', '0'),
                       ('lock_screen_lock_after_timeout', '0'), ('lockscreen.power_button_instantly_locks', '1')]:
        shell('settings', 'put', 'secure', key, value)
    shell('settings', 'put', 'system', 'screen_off_timeout', '600000')
    response = shell('locksettings', 'set-pin', PIN)
    assert 'success' in response.lower() or 'set to' in response.lower(), response
    pin_set = True
    broadcast('PRIVACY_SEED')
    id = rows()[-1]['id']
    shell('input', 'keyevent', 'KEYCODE_HOME')
    shell('input', 'keyevent', 'KEYCODE_SLEEP')
    time.sleep(2)
    deadline = time.monotonic() + 90
    reminder = None
    while time.monotonic() < deadline:
        reminder = next(r for r in rows() if r['id'] == id)
        if reminder.get('attempts') == 1:
            break
        time.sleep(1)
    assert reminder and reminder.get('attempts') == 1, 'Privacy test reminder did not fire'
    broadcast('SNAPSHOT')
    snapshot = json.loads(adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/notification-probe.json'))
    posted = next(n for n in snapshot if n['id'] == id)
    result['notification_snapshot'] = posted
    assert posted['text'] == BODY and BODY not in posted['publicText'], snapshot
    assert posted['visibility'] == 0 and not posted['fullscreen'], snapshot
    assert posted['vibrationEnabled'] and posted['pattern'] == [0, 200, 200, 200, 200, 200], snapshot
    result['channel_three_pulse_pattern'] = True
    shell('am', 'kill', PACKAGE)
    time.sleep(2)
    assert not shell('pidof', PACKAGE, check=False), 'App process is still alive'
    shell('input', 'keyevent', 'KEYCODE_WAKEUP')
    locked = wait_ui(False)
    shell('cmd', 'statusbar', 'collapse', check=False)
    # MENU can bypass the emulator keyguard and leave ENTER focused on a notification.
    # Open and verify the real PIN bouncer before sending any credentials.
    pin_ui = ''
    for _ in range(3):
        shell('input', 'swipe', '500', '1600', '500', '400', '350')
        pin_ui = ui()
        if 'pinEntry' in pin_ui:
            break
        time.sleep(1)
    assert 'pinEntry' in pin_ui, f'PIN entry did not open: {pin_ui}'
    shell('input', 'text', PIN)
    # Some builds auto-confirm a completed PIN. Never send ENTER into the unlocked shade.
    if 'pinEntry' in ui():
        shell('input', 'keyevent', 'KEYCODE_ENTER')
    unlocked = wait_ui(True)
    result['app_process_after_unlock'] = shell('pidof', PACKAGE, check=False)
    assert not shell('pidof', PACKAGE, check=False), 'Unlock depended on restarting the app'
    assert next(r for r in rows() if r['id'] == id)['attempts'] == 1, 'Unlock consumed another alert attempt'
    shell('cmd', 'statusbar', 'collapse', check=False)
    shell('input', 'keyevent', 'KEYCODE_SLEEP')
    time.sleep(2)
    shell('input', 'keyevent', 'KEYCODE_WAKEUP')
    relocked = wait_ui(False)
    assert not shell('pidof', PACKAGE, check=False), 'Relock depended on the app'
    result['lock_unlock_relock_without_app_process'] = True
    result['notification_snapshot'] = posted
    print('PASS: SystemUI hides, reveals, and hides the body again while the app process is dead', flush=True)
    print('PASS: channel stores the requested three-pulse waveform; physical motor behavior is unverified', flush=True)
finally:
    if not result['lock_unlock_relock_without_app_process']:
        try:
            print('Privacy failure diagnostic:', json.dumps(result, ensure_ascii=False), flush=True)
            log = shell('logcat', '-d', '-t', '1000', check=False)
            print('\n'.join(line for line in log.splitlines() if PACKAGE in line or 'Keyguard' in line), flush=True)
        except Exception as error:
            print('Could not capture privacy diagnostics:', str(error), flush=True)
    if pin_set:
        shell('locksettings', 'clear', '--old', PIN, check=False)
    for key, value in original.items():
        if value == 'null':
            shell('settings', 'delete', 'secure', key, check=False)
        else:
            shell('settings', 'put', 'secure', key, value, check=False)
    shell('settings', 'put', 'system', 'screen_off_timeout', timeout_before, check=False)
    RESULT.write_text(json.dumps(result, ensure_ascii=False, indent=2))
