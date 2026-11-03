"""Reproduce the local art metadata: npm ci --prefix tool/character-art, then python3 tool/character-art/prepare.py (requires Pillow). Does not rewrite artwork."""
import json
from pathlib import Path
import subprocess
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
catalog = json.loads((ROOT / 'assets/character_art/art_catalog.json').read_text())
rows = {row['asset']: row for row in catalog.values()}
pixels, frames = {}, {}
for asset, row in sorted(rows.items()):
    im = Image.open(ROOT / asset).convert('RGBA')
    box = im.getchannel('A').point(lambda a: 255 if a > 32 else 0).getbbox() or (0, 0, im.width, im.height)
    left, top, right, bottom = box
    frames[asset] = {'bounds': list(box), 'focus': [round((left + right) / 2, 2), round(top + (bottom - top) * .25, 2)]}
    # Transparent RGB is not colour evidence. Preserve source colours without compositing on white/black.
    pixels[asset] = [(255 << 24) | (r << 16) | (g << 8) | b
        for y in range(0, im.height, 4) for x in range(0, im.width, 4)
        for r, g, b, a in [im.getpixel((x, y))] if a >= 240]
    if not pixels[asset]:
        pixels[asset] = [(255 << 24) | (r << 16) | (g << 8) | b for r, g, b, a in im.getdata() if a > 32]
result = subprocess.run(['node', str(Path(__file__).with_name('palette.mjs'))], input=json.dumps(pixels), text=True, capture_output=True, check=True)
styles = json.loads(result.stdout)
for asset, frame in frames.items():
    styles[asset].update(frame)
# The focal landmark is manually checked against these two review/reference assets.
styles['assets/character_banners/genshin_keqing.webp']['focus'] = [416, 137]
styles['assets/character_portraits/honkai_suit-129915.webp']['focus'] = [216, 148]
output = {'generator': 'Google Material Color Utilities 0.4.0 / QuantizerCelebi + Score + Scheme', 'images': styles}
(ROOT / 'assets/character_art/art_styles.json').write_text(json.dumps(output, ensure_ascii=False, separators=(',', ':')) + '\n')
print(f'Prepared {len(styles)} image frames and light/dark palettes')
