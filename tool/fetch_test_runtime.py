"""Pinned Linux CPU runtime for the real Silero inference test in cloud CI."""
import hashlib
import os
from pathlib import Path
import tarfile
import urllib.request
import shutil
name = 'sherpa-onnx-v1.13.8-linux-x64-shared-lib'
root = Path(__file__).resolve().parents[1]
archive = root / ('model-downloads/' + name + '.tar.bz2')
archive.parent.mkdir(exist_ok=True)
if not archive.exists():
    with urllib.request.urlopen('https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/' + name + '.tar.bz2', timeout=120) as response, archive.open('wb') as output:
        shutil.copyfileobj(response, output)
if hashlib.sha256(archive.read_bytes()).hexdigest() != '3892d184be41027e18165e67f549cd4e4cdd8dcd73ac5579e97afd55e14e30b6':
    archive.unlink()
    raise SystemExit('Test runtime SHA-256 mismatch')
target = root / 'tool/test-runtime'
target.mkdir(exist_ok=True)
with tarfile.open(archive) as tar:
    tar.extractall(target, filter='data')
directory = next(target.rglob('libsherpa-onnx-c-api.so')).parent
if os.environ.get('GITHUB_ENV'):
    with open(os.environ['GITHUB_ENV'], 'a') as env:
        env.write('SHERPA_TEST_LIB=' + str(directory) + '\n')
print('Prepared pinned Linux inference runtime')
