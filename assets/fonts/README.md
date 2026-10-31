# MemoSerif

`MemoSerif-Regular.otf` is **Noto Serif CJK SC Regular**, subset to GB2312
(6763 hanzi) plus ASCII and the punctuation the UI uses. 2.3MB instead of the
26MB TTC.

Regenerate with:

```bash
python3 - <<'PY'
chars = set()
for hi in range(0xA1, 0xF8):
    for lo in range(0xA1, 0xFF):
        try: chars.add(bytes([hi, lo]).decode('gb2312'))
        except Exception: pass
chars |= {chr(c) for c in range(0x20, 0x7F)}
open('/tmp/chars.txt', 'w').write(''.join(sorted(chars)))
PY
python3 -m fontTools.subset /usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc \
  --font-number=2 --text-file=/tmp/chars.txt --output-file=MemoSerif-Regular.otf \
  --layout-features='kern,liga,vert,vrt2' --drop-tables+=DSIG \
  --desubroutinize --no-hinting
```

Only the characters present here can render in the serif. Anything outside
GB2312 falls back to the system sans, which is why the face is used for titles
and not for user content that may contain rare characters.

Licensed under the SIL Open Font License 1.1 — see `LICENSE-NotoSerifCJK.txt`.
