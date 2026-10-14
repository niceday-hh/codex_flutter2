"""Consume CI secrets without logging them. No automatic fallback to a new test signature."""
import base64
import os
from pathlib import Path

kind = 'unsigned'
if os.environ.get('KEYSTORE_BASE64'):
    for name in ['STORE_PASSWORD', 'KEY_PASSWORD', 'KEY_ALIAS']:
        if not os.environ.get(name): raise SystemExit('Incomplete signing secrets')
    key = Path(os.environ['RUNNER_TEMP']) / 'memo-release.p12'
    key.write_bytes(base64.b64decode(os.environ['KEYSTORE_BASE64'], validate=True))
    key.chmod(0o600)
    def prop(s): return s.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r')
    Path('android/key.properties').write_text(
        f'storeFile={prop(str(key))}\nstorePassword={prop(os.environ["STORE_PASSWORD"])}\n'
        f'keyPassword={prop(os.environ["KEY_PASSWORD"])}\nkeyAlias={prop(os.environ["KEY_ALIAS"])}\n')
    kind = 'release'
else:
    print('::notice::Fixed signing secrets are not configured. Tests continue; no unsigned APK will be published as an installable Release.')
Path('signing-kind.txt').write_text(kind)
with open(os.environ['GITHUB_OUTPUT'], 'a') as f: f.write(f'signing={kind}\n')
