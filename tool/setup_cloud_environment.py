#!/usr/bin/env python3
"""Install the repository's Android toolchain into a user-writable directory.

No signing keys, GitHub credentials or release actions are used here.
Run from an Ubuntu 24.04 x86_64 cloud environment with Python 3.12.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import tarfile
import tempfile
import urllib.request
import urllib.parse
import zipfile

REPO = Path(__file__).resolve().parent.parent
LOCK = json.loads((REPO / 'tool/cloud-environment.lock.json').read_text())
ROOT = Path(os.environ.get('MEMO_CLOUD_ROOT', REPO / '.codex/toolchain')).resolve()


def digest(path, algorithm):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, algorithm).hexdigest()


def download(name, spec):
    target = ROOT / 'downloads' / spec['url'].rsplit('/', 1)[-1]
    target.parent.mkdir(parents=True, exist_ok=True)
    algorithm = 'sha256' if 'sha256' in spec else 'sha1'
    if target.exists() and digest(target, algorithm) == spec[algorithm]:
        print(f'{name}: verified cached archive', flush=True)
        return target
    temporary = target.with_suffix(target.suffix + '.part')
    print(f'{name}: downloading official archive', flush=True)
    try:
        request = urllib.request.Request(spec['url'], headers={'User-Agent': 'memo-cloud-setup/1'})
        with urllib.request.urlopen(request, timeout=180) as response, temporary.open('wb') as output:
            shutil.copyfileobj(response, output, 4 * 1024 * 1024)
        if digest(temporary, algorithm) != spec[algorithm]:
            raise RuntimeError(f'{name}: archive checksum mismatch')
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    print(f'{name}: download and checksum passed', flush=True)
    return target


def install_archive(name, archive, destination, marker):
    stamp = destination / '.memo-cloud-version'
    if stamp.is_file() and stamp.read_text().strip() == marker:
        print(f'{name}: installed {marker}', flush=True)
        return
    if destination.exists():
        raise RuntimeError(f'Refusing to replace an unrecognized installation: {destination}')
    with tempfile.TemporaryDirectory(prefix='extract-', dir=ROOT) as temp:
        staging = Path(temp)
        if zipfile.is_zipfile(archive):
            with zipfile.ZipFile(archive) as bundle:
                for item in bundle.infolist():
                    output = (staging / item.filename).resolve()
                    if not output.is_relative_to(staging):
                        raise RuntimeError('Unsafe archive path')
                    if stat.S_ISLNK(item.external_attr >> 16):
                        link = bundle.read(item).decode('utf-8')
                        if Path(link).is_absolute() or not (output.parent / link).resolve().is_relative_to(staging):
                            raise RuntimeError('Unsafe archive symlink')
                        output.parent.mkdir(parents=True, exist_ok=True)
                        output.symlink_to(link)
                        continue
                    bundle.extract(item, staging)
                    permissions = item.external_attr >> 16 & 0o777
                    if permissions:
                        output.chmod(permissions)
        else:
            with tarfile.open(archive) as bundle:
                bundle.extractall(staging, filter='data')
        entries = list(staging.iterdir())
        if len(entries) != 1 or not entries[0].is_dir():
            raise RuntimeError(f'Unexpected archive layout: {name}')
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(entries[0]), destination)
        stamp.write_text(marker + '\n')
    print(f'{name}: installed {marker}', flush=True)


def environment():
    env = dict(os.environ)
    env.update({
        'MEMO_CLOUD_ROOT': str(ROOT), 'JAVA_HOME': str(ROOT / 'jdk'),
        'FLUTTER_ROOT': str(ROOT / 'flutter'),
        'ANDROID_HOME': str(ROOT / 'android-sdk'),
        'ANDROID_SDK_ROOT': str(ROOT / 'android-sdk'),
        'ANDROID_AVD_HOME': str(ROOT / 'avd'),
        'PUB_CACHE': str(ROOT / 'pub-cache'),
        'GRADLE_USER_HOME': str(ROOT / 'gradle'),
        'TMPDIR': str(ROOT / 'tmp'),
        'FLUTTER_SUPPRESS_ANALYTICS': 'true', 'DART_SUPPRESS_ANALYTICS': 'true',
        'MEMO_RUN_REBOOT_TESTS': '0',
    })
    paths = ['flutter/bin', 'jdk/bin', 'android-sdk/cmdline-tools/latest/bin',
             'android-sdk/platform-tools', 'android-sdk/emulator', 'android-sdk/cmake/3.22.1/bin']
    env['PATH'] = os.pathsep.join(str(ROOT / p) for p in paths) + os.pathsep + env.get('PATH', '')
    # Explicit paths also work in constrained runtimes where ELF $ORIGIN is unavailable.
    (ROOT / 'tmp').mkdir(parents=True, exist_ok=True)
    env['LD_LIBRARY_PATH'] = os.pathsep.join([str(ROOT / 'jdk/lib'), str(ROOT / 'jdk/lib/server'),
                                            str(ROOT / 'android-sdk/emulator/lib64'),
                                            str(ROOT / 'android-sdk/emulator/lib64/qt/lib')]
                                            + ([env['LD_LIBRARY_PATH']] if env.get('LD_LIBRARY_PATH') else []))
    return env


def run(command, **kwargs):
    print('+ ' + ' '.join(map(str, command)), flush=True)
    return subprocess.run(list(map(str, command)), cwd=REPO, env=environment(), check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk-packages', action='store_true', help='Install Android build packages')
    parser.add_argument('--emulators', action='store_true', help='Also install API 33/35 images and create AVDs')
    parser.add_argument('--accept-android-licenses', action='store_true',
                        help='Accept Android SDK licenses for this installation')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() != 'x86_64':
        raise SystemExit('This lock targets Linux x86_64, matching the repository CI.')
    ROOT.mkdir(parents=True, exist_ok=True)
    tools = {name: LOCK[key] for name, key in (
        ('flutter', 'flutter'), ('jdk', 'jdk'), ('android', 'android_command_line_tools'))}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        archives = dict(zip(tools, pool.map(lambda key: download(key, tools[key]), tools)))
    install_archive('Flutter', archives['flutter'], ROOT / 'flutter', LOCK['flutter']['version'])
    install_archive('Temurin JDK', archives['jdk'], ROOT / 'jdk', LOCK['jdk']['version'])
    install_archive('Android CLI', archives['android'], ROOT / 'android-sdk/cmdline-tools/latest',
                    LOCK['android_command_line_tools']['version'])
    run(['java', '-version'])
    run(['javac', '-version'])
    if args.sdk_packages or args.emulators:
        manager = ROOT / 'android-sdk/cmdline-tools/latest/bin/sdkmanager'
        sdk_flag = '--sdk_root=' + str(ROOT / 'android-sdk')
        manager_args = [manager, sdk_flag]
        proxy = os.environ.get('HTTPS_PROXY') or os.environ.get('https_proxy')
        if proxy:
            parsed = urllib.parse.urlsplit(proxy)
            if parsed.username or parsed.password:
                raise RuntimeError('Configure SDK networking without embedding proxy credentials in arguments')
            if parsed.hostname:
                manager_args += ['--proxy=http', '--proxy_host=' + parsed.hostname,
                                 '--proxy_port=' + str(parsed.port or 80)]
        if args.accept_android_licenses:
            run([*manager_args, '--licenses'], input='y\n' * 100, text=True, timeout=180)
        packages = LOCK['android_packages'] + (LOCK['emulator_packages'] if args.emulators else [])
        run([*manager_args, *packages], input='y\n' * 100 if args.accept_android_licenses else '', text=True)
        if args.emulators:
            for api in (33, 35):
                name = f'memo-api{api}'
                if not (ROOT / 'avd' / (name + '.ini')).exists():
                    run(['avdmanager', 'create', 'avd', '--name', name, '--package',
                         f'system-images;android-{api};google_apis;x86_64', '--device', 'pixel_6'],
                        input='no\n', text=True)
    # A partial install must not be reported as a usable Flutter environment.
    run(['flutter', '--version'])
    print('Toolchain ready. In each shell: source tool/cloud_env.sh', flush=True)


if __name__ == '__main__':
    main()
