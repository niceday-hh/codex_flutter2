"""Pinned Voine VITS-MNN weights; verify every resource and remove AISHELL assets."""
import hashlib
import json
from pathlib import Path
import urllib.request

def prepare():
    lock = json.loads(Path('tool/vits_model.lock.json').read_text())
    target = Path('assets/tts'); target.mkdir(parents=True, exist_ok=True)
    cache = Path('model-downloads/vits-mnn'); cache.mkdir(parents=True, exist_ok=True)
    manifest = {'model': 'voine-vits-uma-genshin-honkai-mnn', 'commit': lock['upstream_commit'],
                'sample_rate': 22050, 'speaker_count': 804, 'files': lock['files']}
    for name, entry in lock['files'].items():
        f = cache / name
        if not f.exists() or f.stat().st_size != entry['bytes'] or hashlib.sha256(f.read_bytes()).hexdigest() != entry['sha256']:
            base = 'raw.githubusercontent.com' if name.endswith('.json') else 'media.githubusercontent.com/media'
            url = f"https://{base}/Voine/VITS-MNN/{lock['upstream_commit']}/app/src/main/assets/mnn/{name}"
            temporary = f.with_suffix('.download'); urllib.request.urlretrieve(url, temporary)
            assert temporary.stat().st_size == entry['bytes'] and hashlib.sha256(temporary.read_bytes()).hexdigest() == entry['sha256'], f'Invalid VITS resource: {name}'
            temporary.replace(f)
        (target / name).write_bytes(f.read_bytes())
    config = json.loads((target / 'config.json').read_text())
    assert len(config['speakers']) == 804 and config['data']['sampling_rate'] == 22050
    for old in target.iterdir():
        if old.name not in lock['files'] and old.name not in ('.keep', 'manifest.json'): old.unlink()
    (target / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    print('Prepared VITS-MNN:', sum(v['bytes'] for v in lock['files'].values()), 'bytes; 804 speaker entries; 22050 Hz')

if __name__ == '__main__': prepare()
