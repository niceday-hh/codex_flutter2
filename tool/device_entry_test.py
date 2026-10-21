"""Observe one Android task across launcher/notification/external entry and preview requests with touch feedback off."""
import json
from pathlib import Path
import subprocess
import time

PACKAGE = 'com.niceday.memo.stable'
ACTIVITY = f'{PACKAGE}/com.niceday.memo.MainActivity'
RECEIVER = f'{PACKAGE}/com.niceday.memo.DebugAlarmProbe'
def adb(*args, check=True):
    p = subprocess.run(['adb', *args], text=True, capture_output=True, timeout=45)
    if check and p.returncode: raise RuntimeError(p.stdout + p.stderr)
    return p.stdout.strip()
def shell(*args): return adb('shell', *args)
def probe(action): return shell('am', 'broadcast', '--receiver-foreground', '-n', RECEIVER, '-a', action)
def tasks():
    probe('ENTRY_SNAPSHOT')
    rows = json.loads(adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/entry-probe.json'))
    return [r for r in rows if r['base'] == 'com.niceday.memo.MainActivity']
sdk = shell('getprop', 'ro.build.version.sdk')
report = {'single_task_reused': False, 'external_document_flags_reused': False,
          'touch_setting_preserved': False, 'physical_vibration_verified': False, 'reboot_tests_run': False}
original = shell('settings', 'get', 'system', 'haptic_feedback_enabled')
try:
    probe('ENTRY_PREPARE'); probe('REMOVE_TASK')
    shell('input', 'keyevent', 'KEYCODE_WAKEUP'); shell('wm', 'dismiss-keyguard')
    shell('am', 'start', '-W', '-n', ACTIVITY, '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER')
    time.sleep(1)
    initial = tasks(); assert len(initial) == 1, initial
    task_id = initial[0]['taskId']
    observed = []
    for action, flags, uri in [
        ('android.intent.action.MAIN', '0x10000000', ''),
        ('com.niceday.memo.OPEN', '0x34000000', 'memo://reminder/0'),
        ('com.niceday.memo.RELIABILITY', '0x34000000', ''),
        ('com.niceday.memo.OPEN', '0x18080000', 'memo://external/0')]:
        shell('input', 'keyevent', 'KEYCODE_HOME')
        args = ['am', 'start', '-W', '-n', ACTIVITY, '-a', action, '-f', flags]
        if uri: args += ['-d', uri]
        shell(*args)
        current = tasks(); observed.append(current)
        assert len(current) == 1 and current[0]['taskId'] == task_id and current[0]['activities'] == 1, current
    report.update(single_task_reused=True, external_document_flags_reused=True, observed_tasks=observed)
    shell('settings', 'put', 'system', 'haptic_feedback_enabled', '0')
    probe('VIBRATION_PREVIEW')
    vibration = json.loads(adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/vibration-probe.json'))
    assert vibration.get('requested') or vibration.get('hardware_absent'), vibration
    assert shell('settings', 'get', 'system', 'haptic_feedback_enabled') == '0'
    report.update(touch_setting_preserved=True, notification_preview_request=vibration)
finally:
    if original == 'null': shell('settings', 'delete', 'system', 'haptic_feedback_enabled')
    else: shell('settings', 'put', 'system', 'haptic_feedback_enabled', original)
    Path(f'device-entry-test-results-api{sdk}.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print('Entry and vibration checks passed:', json.dumps(report), flush=True)
