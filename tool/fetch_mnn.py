"""Pinned MNN source; CPU-only Android runtime compiled for each requested ABI."""
import hashlib
from pathlib import Path
import shutil
import tarfile
import urllib.request

COMMIT = 'efdea1d0e24ed29b4650d7bba9942236cfc7bc3e'
SHA256 = '1e60082243886efb52908c497a89e09d24f1aae072be7751b4e1e4ecc47676eb'
def prepare():
    target = Path('vendor/MNN')
    if (target / '.memo-source-sha256').exists() and (target / '.memo-source-sha256').read_text() == SHA256: return
    cache = Path('model-downloads'); cache.mkdir(exist_ok=True)
    archive = cache / 'mnn-efdea1d.tar.gz'
    if not archive.exists(): urllib.request.urlretrieve(f'https://codeload.github.com/alibaba/MNN/tar.gz/{COMMIT}', archive)
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == SHA256, 'MNN source checksum mismatch'
    stage = Path('vendor/mnn-stage'); shutil.rmtree(stage, ignore_errors=True); stage.mkdir(parents=True)
    with tarfile.open(archive) as tar: tar.extractall(stage, filter='data')
    shutil.rmtree(target, ignore_errors=True)
    (stage / f'MNN-{COMMIT}').rename(target); stage.rmdir()
    (target / '.memo-source-sha256').write_text(SHA256)
    print('Prepared pinned MNN CPU runtime source', COMMIT)
if __name__ == '__main__': prepare()
