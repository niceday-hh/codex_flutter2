"""Generate v0.9.4-cap / bounded-pause real-model WAV comparisons in an isolated debug-only Android Activity."""
import array
import io
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time
import wave

PACKAGE = 'com.niceday.memo.stable'
out = Path('prosody-audit')
out.mkdir(exist_ok=True)

def adb(*args, binary=False, check=True):
    result = subprocess.run(['adb', *args], capture_output=True, timeout=45)
    if check and result.returncode:
        raise RuntimeError(result.stderr.decode(errors='replace'))
    return result.stdout if binary else result.stdout.decode(errors='replace')

adb('install', '-r', 'build/app/outputs/flutter-apk/app-debug.apk')
adb('shell', 'am', 'force-stop', PACKAGE)
adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
adb('shell', 'wm', 'dismiss-keyguard', check=False)
adb('shell', 'am', 'start', '-n', f'{PACKAGE}/com.niceday.memo.DebugProsodyActivity')
deadline = time.monotonic() + 720
report = None
while time.monotonic() < deadline:
    raw = adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/prosody-audit/result.json', check=False)
    try:
        report = json.loads(raw)
        break
    except ValueError:
        time.sleep(2)
if report is None:
    print(adb('shell', 'logcat', '-d', '-t', '400', check=False), flush=True)
    raise AssertionError('Prosody model audit did not complete')
(out / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
assert report.get('success'), report
assert len(report['samples']) == 3
for sample in report['samples']:
    name = sample['file']
    assert re.fullmatch(r'stage-[34]-rate-[68]\.wav', name)
    raw = adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/prosody-audit/' + name, binary=True)
    (out / name).write_bytes(raw)
    with wave.open(io.BytesIO(raw)) as wav:
        assert (wav.getframerate(), wav.getnchannels(), wav.getsampwidth()) == (22050, 1, 2)
        pcm = array.array('h', wav.readframes(wav.getnframes()))
        peak = max(abs(v) for v in pcm)
        assert peak > 3 and wav.getnframes() > 22050, 'Invalid synthesized speech'
        sample['frames'] = wav.getnframes()
        sample['peak_pcm16'] = peak
    # Low-energy windows are a measurement, not linguistic alignment or a naturalness score.
    hop = 220
    threshold = (32768 * 10 ** (-38 / 20)) ** 2
    spans, start = [], None
    for p in range(0, len(pcm) - hop, hop):
        quiet = sum(v * v for v in pcm[p:p + hop]) / hop < threshold
        if quiet and start is None:
            start = p
        elif not quiet and start is not None:
            if (p - start) / 22050 >= .25 and start > 0:
                spans.append({'start': round(start / 22050, 3), 'seconds': round((p - start) / 22050, 3)})
            start = None
    sample['low_energy_gaps'] = spans
samples = {(s['stage'], round(s['rate'], 1)): s for s in report['samples']}
assert samples[4, .6]['frames'] > samples[4, .8]['frames'], '0.6 did not lengthen speech'
for (stage, rate), sample in samples.items():
    if stage != 4:
        continue
    kinds = set()
    for pause in sample['punctuation']:
        kind = pause['kind']; kinds.add(kind)
        floors = {1: 0, 2: 0, 3: .32, 4: .46}
        caps = {1: .14, 2: .26, 3: .46, 4: .65}
        quantum = 256 / 22050
        assert pause['seconds'] + 1e-5 >= floors[kind] / math.sqrt(rate), pause
        assert pause['seconds'] <= caps[kind] / math.sqrt(rate) + quantum + 1e-5, pause
    assert {2, 3} <= kinds, 'Must exercise both clause and sentence windows'
report['slower_rate_verified'] = True
report['synthesized_pause_ranges_verified'] = True
report['source_commit'] = os.environ.get('GITHUB_SHA', '')
(out / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)
