"""Install a self-running AOT UI benchmark; preserve raw engine timings."""
import json
import base64
from pathlib import Path
import subprocess
import sys
import time

package = 'com.niceday.timed_memo'


def parse_measurements(log):
    chunks = {}
    for line in log.splitlines():
        if 'DETAIL_CHUNK:' not in line:
            continue
        index, part, total, data = line.split('DETAIL_CHUNK:', 1)[1].split(':', 3)
        parts = chunks.setdefault(int(index), {'total': int(total), 'parts': {}})
        assert parts['total'] == int(total)
        parts['parts'][int(part)] = data
    rows = []
    for index in sorted(chunks):
        entry = chunks[index]
        assert set(entry['parts']) == set(range(entry['total'])), f'Missing report chunks: {index}'
        raw = ''.join(entry['parts'][i] for i in range(entry['total']))
        rows.append(json.loads(base64.b64decode(raw, validate=True)))
    return rows

def adb(*args):
    return subprocess.check_output(['adb', *args], text=True, timeout=60)

def main(apk, revision):
    adb('install', '-r', apk)
    adb('shell', 'am', 'force-stop', package)
    adb('shell', 'pm', 'clear', package)
    adb('logcat', '-c')
    adb('shell', 'am', 'start', '-n', f'{package}/.MainActivity')
    started = time.monotonic()
    while time.monotonic() - started < 600:
        log = adb('logcat', '-d', '-v', 'brief', 'flutter:I', '*:S')
        if 'Test failed.' in log or 'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' in log:
            Path(f'detail-{revision}.log').write_text(log)
            raise RuntimeError(log[-12000:])
        if 'DETAIL_BENCHMARK_DONE:' in log:
            time.sleep(1)
            log = adb('logcat', '-d', '-v', 'brief', 'flutter:I', '*:S')
            if 'Test failed.' in log or 'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK' in log:
                Path(f'detail-{revision}.log').write_text(log)
                raise RuntimeError(log[-12000:])
            break
        time.sleep(5)
    else:
        Path(f'detail-{revision}.log').write_text(log)
        raise TimeoutError(f'Benchmark did not complete: {log[-12000:]}')
    Path(f'detail-{revision}.log').write_text(log)
    rows = parse_measurements(log)
    done = [json.loads(line.split('DETAIL_BENCHMARK_DONE:', 1)[1]) for line in log.splitlines() if 'DETAIL_BENCHMARK_DONE:' in line][-1]
    assert done['profile'] and done['measurements'] == len(rows) == 54, done
    assert all(row['ui_us'] and len(row['ui_us']) == len(row['raster_us']) for row in rows)
    Path(f'detail-{revision}.json').write_text(json.dumps({'environment': 'Android emulator, SwiftShader, AOT profile; native speech mocked',
        'completion': done, 'measurements': rows}, ensure_ascii=False, indent=2))
    print(f'Completed {revision}: {len(rows)} measurements', flush=True)


if __name__ == '__main__':
    main(*sys.argv[1:])
