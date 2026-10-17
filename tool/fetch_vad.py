"""Prepare the pinned Silero VAD v5 ONNX asset, never trusting a partial download."""
import hashlib
from pathlib import Path
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://raw.githubusercontent.com/snakers4/silero-vad/v5.0/files/silero_vad.onnx'
SHA256 = '6b99cbfd39246b6706f98ec13c7c50c6b299181f2474fa05cbc8046acc274396'
cache = ROOT / 'model-downloads/silero_vad_v5.onnx'
cache.parent.mkdir(exist_ok=True)
if not cache.exists():
    temporary = cache.with_suffix('.partial')
    try:
        with urllib.request.urlopen(URL, timeout=120) as source, temporary.open('wb') as out:
            shutil.copyfileobj(source, out)
        temporary.replace(cache)
    finally:
        temporary.unlink(missing_ok=True)
if hashlib.sha256(cache.read_bytes()).hexdigest() != SHA256:
    cache.unlink()
    raise SystemExit('Silero VAD SHA-256 mismatch')
target = ROOT / 'assets/vad/silero_vad.onnx'
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(cache, target)
print(f'Prepared Silero VAD v5: {target.stat().st_size:,} bytes')
