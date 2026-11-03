"""Expose screenshot Git blob IDs in CI logs for visual review before publication.
The PNGs are not committed to main; the final release also carries their ZIP.
"""
import base64
import json
from pathlib import Path
import subprocess
import os
for path in sorted(Path('character-ui-previews').glob('*.png')):
    request = json.dumps({'content': base64.b64encode(path.read_bytes()).decode(), 'encoding': 'base64'})
    result = subprocess.run(['gh', 'api', f'repos/{os.environ["GH_REPO"]}/git/blobs', '--input', '-', '--jq', '.sha'],
        input=request, text=True, capture_output=True, check=True)
    print(f'CHARACTER_PREVIEW_BLOB {path.name} {result.stdout.strip()}', flush=True)
