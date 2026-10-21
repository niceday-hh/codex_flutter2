"""Actual Android TTS synthesis and native cached playback; never reboot a device."""
import json
import array
import io
import subprocess
import time
import wave
from pathlib import Path
from device_preferences import read_runtime, await_created

PACKAGE = 'com.niceday.memo.stable'
RECEIVER = f'{PACKAGE}/com.niceday.memo.DebugAlarmProbe'
ACTIVITY = f'{PACKAGE}/com.niceday.memo.MainActivity'

def adb(*args, check=True):
    p = subprocess.run(['adb', *args], capture_output=True, text=True, timeout=45)
    if check and p.returncode:
        raise RuntimeError(f'ADB {args}: {p.stdout} {p.stderr}')
    return p.stdout.strip()

def shell(*args, **kwargs):
    return adb('shell', *args, **kwargs)

def probe(action, *extras):
    return shell('am', 'broadcast', '--receiver-foreground', '-n', RECEIVER, '-a', action, *extras)

def runtime():
    return read_runtime(adb, PACKAGE)

def events():
    return json.loads(runtime().get('trace', '[]'))

def wait(predicate, timeout, label):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.5)
    raise AssertionError(label)

def state():
    probe('SPEECH_STATUS')
    return json.loads(adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/speech-probe.json'))

def current(id):
    return next(r for r in json.loads(runtime()['reminders']) if r['id'] == id)

def wave_stats():
    names=adb('exec-out','run-as',PACKAGE,'ls','files/speech-audio').splitlines()
    values=[]
    for name in names:
        if not name.endswith('.wav'): continue
        raw=subprocess.run(['adb','exec-out','run-as',PACKAGE,'cat','files/speech-audio/'+name],capture_output=True,check=True,timeout=45).stdout
        with wave.open(io.BytesIO(raw),'rb') as wav:
            assert wav.getframerate()==22050 and wav.getnchannels()==1 and wav.getsampwidth()==2
            samples=array.array('h',wav.readframes(wav.getnframes()))
            peak=max(abs(v) for v in samples)
            assert wav.getnframes()>2205 and peak>3, 'Synthesized fixture has no speech signal'
            values.append({'sample_rate':wav.getframerate(),'frames':wav.getnframes(),'peak_pcm16':peak})
    assert len(values)>=2, 'Generic and body audio must both be synthesized'
    return values

def prepare(hide):
    probe('CLEAR')
    shell('input', 'keyevent', 'KEYCODE_WAKEUP')
    shell('wm', 'dismiss-keyguard', check=False)
    shell('am', 'start', '-n', ACTIVITY)
    row = await_created(probe('SPEECH_SEED', '--ez', 'hide', str(hide).lower()), runtime)
    wait(lambda: 'preparing=true' in probe('PREPARE_SPEECH'), 45, 'Flutter speech bridge did not resume')
    wait(lambda: next(r for r in state()['reminders'] if r['id'] == row['id'])['speechState'] == 'ready', 120, 'On-device speech synthesis failed')
    probe('RETIME_SPEECH', '--ei', 'id', str(row['id']))
    return row['id'], current(row['id'])['nextTrigger']

def killed():
    shell('input', 'keyevent', 'KEYCODE_HOME')
    probe('REMOVE_TASK'); probe('KILL_PROCESS')
    wait(lambda: not shell('pidof', PACKAGE, check=False), 12, 'Process did not exit')

sdk = shell('getprop', 'ro.build.version.sdk')
path = Path(f'device-speech-test-results-api{sdk}.json')
original_timeout = shell('settings', 'get', 'system', 'screen_off_timeout')
shell('settings', 'put', 'system', 'screen_off_timeout', '600000')
result = {'sdk': int(sdk), 'reboot_tests_run': False, 'physical_audio_verified': False}
path.write_text(json.dumps(result, indent=2))
try:
    id, token = prepare(True)
    assert state()['status']['speech']['speakerCount'] == 804
    result['generated_waveforms']=wave_stats()
    result['on_device_synthesis'] = True
    killed(); shell('input', 'keyevent', 'KEYCODE_SLEEP')
    first = wait(lambda: next((e for e in events() if e['type'] == 'speech_played' and e['id'] == id), None), 90, 'Locked generic speech did not start')
    assert first['detail'] == '通用提示或备用铃声', first
    assert not current(id).get('acknowledged'), 'Playback must not mark read'
    result['locked_hidden_body'] = True
    wait(lambda: current(id).get('attempts') == 2 and len([e for e in events() if e['type'] == 'speech_played' and e['id'] == id]) == 2,
         120, 'Unread retry did not reuse cached audio')
    result['unread_retry_cached_audio'] = True

    id, token = prepare(False)
    killed(); shell('input', 'keyevent', 'KEYCODE_SLEEP')
    event = wait(lambda: next((e for e in events() if e['type'] == 'speech_played' and e['id'] == id), None), 90, 'Locked allowed body did not play')
    assert event['detail'] == '正文', event
    result['locked_body_opt_in'] = True

    id, token = prepare(True)
    shell('input', 'keyevent', 'KEYCODE_HOME')
    event = wait(lambda: next((e for e in events() if e['type'] == 'speech_played' and e['id'] == id), None), 90, 'Unlocked body did not play')
    assert event['detail'] == '正文', event
    probe('SPEECH_ACK', '--ei', 'id', str(id), '--el', 'token', str(token))
    wait(lambda: any(e['type'] == 'speech_stopped' and e['id'] == id for e in events()), 10, 'Acknowledgement did not stop playback')
    row = current(id)
    assert row['acknowledged'] and row['retryAt'] == 0
    result['unlocked_body_and_manual_stop'] = True
    probe('REMINDER_AUDIO_EXPORT', '--ei', 'id', str(id))
    exported = json.loads(adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/reminder-audio-probe.json'))
    assert exported['reminderId'] == id and exported['sid'] == 33 and exported['rate'] == 1
    assert exported['body_matches_saved'] and exported['reminder_unchanged'] and exported['export_identical']
    assert exported['bytes'] > 44 and exported['content_resolver_roundtrip']
    result['saved_reminder_audio_export'] = exported
    print('PASS: on-device VITS-MNN synthesis, process-death cached playback, lock privacy, retry, manual stop and saved WAV export', flush=True)
finally:
    shell('settings', 'put', 'system', 'screen_off_timeout', original_timeout, check=False)
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2))
    if not result.get('unlocked_body_and_manual_stop'):
        print('Speech diagnostics:', json.dumps({'result': result, 'events': events()}, ensure_ascii=False), flush=True)
        print(shell('logcat', '-d', '-t', '600', check=False), flush=True)
    probe('CLEAR')
