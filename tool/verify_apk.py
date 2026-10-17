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
    manifest = json.loads(z.read('assets/flutter_assets/assets/tts/manifest.json'))
    for resource, entry in manifest['files'].items():
        payload = z.read('assets/flutter_assets/assets/tts/' + resource)
        assert len(payload) == entry['bytes'] and hashlib.sha256(payload).hexdigest() == entry['sha256']
    assert manifest['speaker_count'] == 804 and manifest['sample_rate'] == 22050
    assert 'lib/arm64-v8a/libmemo_vits.so' in z.namelist(), 'Missing MNN JNI runtime'
    catalog_bytes = z.read('assets/voice_catalog.json')
    assert catalog_bytes == z.read('assets/flutter_assets/native/app/src/main/assets/voice_catalog.json'), 'Voice groups differ between native and Flutter'
    assert catalog_bytes == Path('native/app/src/main/assets/voice_catalog.json').read_bytes(), 'Voice groups differ from source'
    catalog = json.loads(catalog_bytes)
    assert len(catalog['voices']) == 804
    assert all(v['language'] in ('zh', 'ja') and v['gender'] in ('male', 'female', 'unknown') for v in catalog['voices'])
    assert not any(p.startswith('assets/flutter_assets/assets/tts/') and p.endswith(('.onnx', '.fst', '.far')) for p in z.namelist()), 'AISHELL assets must be removed'
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
    'tts_model': 'voine-vits-uma-genshin-honkai-mnn', 'tts_speakers': 804, 'tts_sample_rate': 22050,
    'reboot_tests_run': False,
    'tests': ['flutter analyze', 'flutter test', 'JVM schedule checks', 'native notification/backup/boot tests'],
    'honor_100_tested': False}, ensure_ascii=False, indent=2))
