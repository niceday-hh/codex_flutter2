#!/usr/bin/env python3
"""Record real tool availability without treating a missing emulator as a pass."""
import argparse
import json
import os
from pathlib import Path
import subprocess
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', action='store_true')
    args = parser.parse_args()
    results = [
        probe('Java 17', ['java', '-version'], '17.'),
        probe('Java compiler', ['javac', '-version'], '17.'),
        probe('Flutter', ['flutter', '--version', '--machine'], LOCK['flutter']['version']),
        probe('Android command-line tools', ['sdkmanager', '--version']),
        probe('ADB', ['adb', 'version']),
        probe('CMake', ['cmake', '--version'], '3.22.1'),
        probe('NDK compiler', [str(ROOT / 'android-sdk/ndk/27.0.12077973/toolchains/llvm/prebuilt/linux-x86_64/bin/clang'), '--version'], 'clang version 18.'),
        probe('Android packaging tool', [str(ROOT / 'android-sdk/build-tools/36.0.0/aapt2'), 'version']),
    ]
    for package in LOCK['android_packages']:
        path = ROOT / 'android-sdk' / package.replace(';', '/')
        results.append({'name': package, 'passed': path.is_dir(), 'path': str(path)})
    emulator = None
    if args.emulator:
        emulator = [probe('Emulator version', ['emulator', '-version']),
                    probe('Emulator acceleration', ['emulator', '-accel-check']),
                    probe('Configured AVDs', ['emulator', '-list-avds'])]
    report = {'toolchain_passed': all(r['passed'] for r in results), 'checks': results,
              'kvm_device_present': Path('/dev/kvm').exists(), 'emulator': emulator,
              'signing_configured': (REPO / 'android/key.properties').is_file()}
    target = REPO / '.codex/state/environment-check.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    for result in results + (emulator or []):
        print(('PASS' if result['passed'] else 'FAIL') + ': ' + result['name'])
    print('Detailed report:', target)
    raise SystemExit(0 if report['toolchain_passed'] else 1)


if __name__ == '__main__':
    main()
