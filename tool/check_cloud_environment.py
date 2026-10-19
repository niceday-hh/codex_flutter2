#!/usr/bin/env python3
"""Record real tool availability without treating a missing emulator as a pass."""
import argparse
import ctypes
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from setup_cloud_environment import LOCK, REPO, ROOT, environment


def probe(name, command, expected=None):
    try:
        result = subprocess.run(command, cwd=REPO, env=environment(), capture_output=True,
                                text=True, timeout=90)
        output = (result.stdout + result.stderr).strip()
        passed = result.returncode == 0 and (expected is None or expected in output)
        return {'name': name, 'passed': passed, 'exit_code': result.returncode,
                'output': output[-6000:]}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {'name': name, 'passed': False, 'output': str(error)}


def host_diagnostics():
    """Observe host support without changing the runtime or emulating /proc."""
    host = {'proc_self_maps_readable': False,
            'kvm_device_present': Path('/dev/kvm').exists()}
    try:
        with open('/proc/self/maps') as stream:
            stream.read(1)
        host['proc_self_maps_readable'] = True
    except OSError as error:
        host['proc_self_maps_error'] = str(error)
    try:
        libc = ctypes.CDLL(None)
        libc.pthread_self.restype = ctypes.c_void_p
        libc.pthread_getattr_np.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        # Larger than glibc's pthread_attr_t on the pinned Linux x86_64 host.
        attributes = ctypes.create_string_buffer(256)
        result = libc.pthread_getattr_np(libc.pthread_self(), ctypes.byref(attributes))
        host['main_thread_stack_attributes'] = {
            'return_code': result, 'error': os.strerror(result) if result else None}
        if result == 0:
            libc.pthread_attr_destroy(ctypes.byref(attributes))
    except (OSError, AttributeError) as error:
        host['main_thread_stack_attributes'] = {'error': str(error)}
    return host


def dart_smoke_test():
    # A successful `dart --version` does not prove the VM can execute code.
    environment()
    with tempfile.TemporaryDirectory(prefix='dart-smoke-', dir=ROOT / 'tmp') as temp:
        source = Path(temp) / 'smoke.dart'
        source.write_text("void main() { print('DART_EXECUTION_OK'); }\n")
        return probe('Dart execution', [str(ROOT / 'flutter/bin/cache/dart-sdk/bin/dart'),
                                      str(source)], 'DART_EXECUTION_OK')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', action='store_true')
    args = parser.parse_args()
    results = [
        probe('Java 17', ['java', '-version'], '17.'),
        probe('Java compiler', ['javac', '-version'], '17.'),
        probe('Dart version', [str(ROOT / 'flutter/bin/cache/dart-sdk/bin/dart'), '--version'],
              LOCK['flutter']['dart']),
        dart_smoke_test(),
        probe('Flutter', ['flutter', '--version', '--machine'], LOCK['flutter']['version']),
        probe('Android command-line tools', ['sdkmanager', '--version']),
        probe('ADB', ['adb', 'version']),
        probe('CMake', ['cmake', '--version'], '3.22.1'),
        probe('NDK compiler', [str(ROOT / 'android-sdk/ndk/27.0.12077973/toolchains/llvm/prebuilt/linux-x86_64/bin/clang'), '--version'], 'clang version 18.'),
        probe('Android packaging tool', [str(ROOT / 'android-sdk/build-tools/36.0.0/aapt2'), 'version']),
    ]
    for package in LOCK['android_packages']:
        path = ROOT / 'android-sdk' / package.replace(';', '/')
        results.append({'name': package, 'passed': (path / 'source.properties').is_file(),
                        'path': str(path), 'package_xml_present': (path / 'package.xml').is_file()})
    emulator = None
    if args.emulator:
        avds = probe('Configured API 33/35 AVDs', ['emulator', '-list-avds'])
        avds['passed'] = avds['passed'] and {'memo-api33', 'memo-api35'}.issubset(
            set(avds['output'].splitlines()))
        emulator = [probe('Emulator version', ['emulator', '-version']),
                    probe('Emulator acceleration', ['emulator', '-accel-check']),
                    probe('Direct acceleration helper',
                          [str(ROOT / 'android-sdk/emulator/emulator-check'), 'accel']), avds]
    report = {'checked_at_utc': datetime.now(timezone.utc).isoformat(),
              'toolchain_passed': all(r['passed'] for r in results), 'checks': results,
              'host': host_diagnostics(), 'free_disk_bytes': shutil.disk_usage(REPO).free,
              'kvm_device_present': Path('/dev/kvm').exists(), 'emulator': emulator,
              'emulator_passed': all(r['passed'] for r in emulator) if emulator is not None else None,
              'signing_configured': (REPO / 'android/key.properties').is_file()}
    target = REPO / '.codex/state/environment-check.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    for result in results + (emulator or []):
        print(('PASS' if result['passed'] else 'FAIL') + ': ' + result['name'])
    print('Detailed report:', target)
    passed = report['toolchain_passed'] and (not args.emulator or report['emulator_passed'])
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
