"""Install a self-running AOT UI benchmark; preserve raw engine timings."""
import json
from pathlib import Path
import subprocess
import sys
import time

apk, revision = sys.argv[1:]
package = 'com.niceday.timed_memo'

def adb(*args):
    return subprocess.check_output(['adb', *args], text=True, timeout=60)

adb('install', '-r', apk)
adb('shell', 'am', 'force-stop', package)
adb('logcat', '-c')
adb('shell', 'am', 'start', '-n', f'{package}/.MainActivity')
started = time.monotonic()
while time.monotonic() - started < 600:
    log = adb('logcat', '-d', '-v', 'brief', 'flutter:I', '*:S')
    if 'DETAIL_BENCHMARK_DONE:' in log:
        break
    if 'Test failed.' in log or 'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' in log:
        Path(f'detail-{revision}.log').write_text(log)
        raise RuntimeError(log[-12000:])
    time.sleep(5)
else:
    Path(f'detail-{revision}.log').write_text(log)
    raise TimeoutError(f'Benchmark did not complete: {log[-12000:]}')
Path(f'detail-{revision}.log').write_text(log)
rows = [json.loads(line.split('DETAIL_FRAME:', 1)[1]) for line in log.splitlines() if 'DETAIL_FRAME:' in line]
done = [json.loads(line.split('DETAIL_BENCHMARK_DONE:', 1)[1]) for line in log.splitlines() if 'DETAIL_BENCHMARK_DONE:' in line][-1]
assert done['profile'] and done['measurements'] == len(rows) == 54, done
assert all(row['ui_us'] and len(row['ui_us']) == len(row['raster_us']) for row in rows)
Path(f'detail-{revision}.json').write_text(json.dumps({'environment': 'Android emulator, SwiftShader, AOT profile; native speech mocked',
    'completion': done, 'measurements': rows}, ensure_ascii=False, indent=2))
print(f'Completed {revision}: {len(rows)} measurements', flush=True)
