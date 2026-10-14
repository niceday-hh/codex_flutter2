import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

version = re.search(r'^version:\s*([^+\s]+)\+(\d+)', Path('pubspec.yaml').read_text(), re.M)
assert version
name, code = version.groups()
assert Path('.release-version').read_text().strip() == f'v{name}'
kind = Path('signing-kind.txt').read_text().strip()
directory = Path('build/app/outputs/flutter-apk')
apk = directory / 'app-release.apk'
with zipfile.ZipFile(apk) as z:
    for entry in ['assets/flutter_assets/assets/models/model.int8.onnx', 'assets/flutter_assets/assets/models/tokens.txt', 'lib/arm64-v8a/libsherpa-onnx-c-api.so']:
        assert entry in z.namelist(), f'Missing APK entry: {entry}'
expected = Path('docs/signing-certificate.sha256').read_text().strip().lower()
if kind == 'release':
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ['ANDROID_HOME'])
    signer = sorted(sdk.glob('build-tools/*/apksigner'), key=lambda p: [int(x) for x in re.findall(r'\d+', p.parent.name)])[-1]
    result = subprocess.run([str(signer), 'verify', '--verbose', '--print-certs', str(apk)], check=True, capture_output=True, text=True)
    digest = re.search(r'certificate SHA-256 digest:\s*([0-9a-fA-F]+)', result.stdout)
    assert digest and digest.group(1).lower() == expected, 'Signing certificate changed; refusing release'
    print('Fixed certificate verified:', expected)
suffix = '' if kind == 'release' else '-unsigned'
renamed = directory / f'timed-memo-{name}-arm64{suffix}.apk'
apk.rename(renamed)
(directory / 'SHA256SUMS.txt').write_text(f'{hashlib.sha256(renamed.read_bytes()).hexdigest()}  {renamed.name}\n')
(directory / 'BUILD_INFO.json').write_text(json.dumps({
    'version': name, 'build': int(code), 'package': 'com.niceday.memo.stable',
    'source_commit': os.environ['GITHUB_SHA'], 'flutter': '3.35.7', 'abi': 'arm64-v8a',
    'signing': kind, 'certificate_sha256': expected if kind == 'release' else None,
    'model': 'paraformer-zh-int8-2025-10-07',
    'tests': ['flutter analyze', 'flutter test', 'JVM schedule checks', 'native notification/backup/boot tests'],
    'honor_100_tested': False}, ensure_ascii=False, indent=2))
