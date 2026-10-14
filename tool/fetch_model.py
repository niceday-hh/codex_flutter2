#!/usr/bin/env python3
"""Download a pinned, digest-verified Chinese int8 model; extract only required files."""
import hashlib
from pathlib import Path
import shutil
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
NAME = "sherpa-onnx-paraformer-zh-int8-2025-10-07"
URL = f"https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/{NAME}.tar.bz2"
DIGEST = "a071ee5419e14adb34d7f970ab98105a45e6608018b168f023ca2e4810744abe"
cache = ROOT / "model-downloads"
cache.mkdir(exist_ok=True)
archive = cache / f"{NAME}.tar.bz2"
if not archive.exists():
    print("Downloading pinned Paraformer Chinese int8 model", flush=True)
    temporary = archive.with_suffix(".partial")
    with urllib.request.urlopen(URL, timeout=120) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output)
    temporary.replace(archive)
actual = hashlib.sha256(archive.read_bytes()).hexdigest()
if actual != DIGEST:
    archive.unlink()
    raise SystemExit("Model archive SHA-256 mismatch; refusing to build")
dest = ROOT / "assets/models"
dest.mkdir(parents=True, exist_ok=True)
with tarfile.open(archive, "r:bz2") as tar:
    for name in ("model.int8.onnx", "tokens.txt"):
        member = tar.getmember(f"{NAME}/{name}")
        if not member.isfile():
            raise SystemExit("Model member is not a regular file")
        source = tar.extractfile(member)
        assert source is not None
        with source, (dest / name).open("wb") as output:
            shutil.copyfileobj(source, output)
        print(f"Prepared {name}: {(dest / name).stat().st_size:,} bytes", flush=True)
