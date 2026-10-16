"""Pinned AISHELL-3 inference resources; exclude training weights and large FAR archive."""
import hashlib
import json
from pathlib import Path
import tarfile
import urllib.request

NAME = 'vits-icefall-zh-aishell3'
URL = f'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/{NAME}.tar.bz2'
SHA256 = 'ab468db3a3308cdd861495e0db2f25d79418a0c00639f74944c7cdf5dd8c6ec1'
FILES = ('model.onnx', 'lexicon.txt', 'tokens.txt', 'phone.fst', 'date.fst', 'number.fst', 'new_heteronym.fst', 'speakers.txt')

def prepare():
    cache = Path('model-downloads'); cache.mkdir(exist_ok=True)
    archive = cache / f'{NAME}.tar.bz2'
    if not archive.exists():
        temporary = archive.with_suffix('.download')
        urllib.request.urlretrieve(URL, temporary)
        temporary.rename(archive)
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == SHA256, 'AISHELL model archive checksum mismatch'
    target = Path('assets/tts'); target.mkdir(parents=True, exist_ok=True)
    manifest = {'model': NAME, 'archive_sha256': SHA256, 'sample_rate': 8000, 'speaker_count': 174, 'files': {}}
    with tarfile.open(archive) as tar:
        for name in FILES:
            member = tar.getmember(f'{NAME}/{name}')
            assert member.isfile() and member.size < 40 * 1024 * 1024
            payload = tar.extractfile(member).read()
            (target / name).write_bytes(payload)
            manifest['files'][name] = {'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}
    speakers = (target / 'speakers.txt').read_text().splitlines()
    assert len(speakers) == 174
    (target / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    print('Prepared AISHELL-3:', sum(v['bytes'] for v in manifest['files'].values()), 'bytes; 174 speakers; FAR excluded')

if __name__ == '__main__':
    prepare()
