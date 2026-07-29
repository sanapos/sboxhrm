"""Merge translated UI chunks into en_ui_map.json and regenerate en_ui_map.g.dart.

Chunks are the Vietnamese fragments that surround interpolated values, e.g. the
"nhân viên" in "$count nhân viên". tr() substitutes them at runtime, so they only
need to live in the main map. Junk keys (regex character classes, code fragments
picked up by the source scanner) are dropped here.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
L10N = os.path.join(os.path.dirname(HERE), 'lib', 'l10n')
MAIN_JSON = os.path.join(HERE, 'en_ui_map.json')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

# Keys that are code fragments or diacritic character classes, never UI copy.
# A stray '}' or '${' means the source scanner cut an interpolation in half.
JUNK = re.compile(
    r'\)\.format\(|\$\{|[{}]|</|^\[[àáảãạăâèéêìíòóôơùúưỳý].*\]$|đ/giờ')


def is_junk(k):
    if JUNK.search(k):
        return True
    # long runs of accented letters with no spaces = diacritic normalisation table
    if ' ' not in k and len(k) > 12 and VN.search(k):
        return True
    return False


def main():
    main_map = json.load(open(MAIN_JSON, encoding='utf-8'))

    # Every chunk seen so far, resolved against the machine output then the map.
    chunks = {}
    p = os.path.join(HERE, 'chunks_en.json')
    if os.path.exists(p):
        chunks.update({k: v for k, v in
                       json.load(open(p, encoding='utf-8')).items() if v})
    p = os.path.join(HERE, 'chunks_all.json')
    if os.path.exists(p):
        for k in json.load(open(p, encoding='utf-8')):
            if k not in chunks and main_map.get(k):
                chunks[k] = main_map[k]

    phrases = {}
    for k, v in chunks.items():
        if not VN.search(k) or is_junk(k):
            continue
        if VN.search(v):          # translation failed — skip, would be a no-op
            continue
        if v.strip().lower() == k.strip().lower():
            continue
        if len(k) < 2:
            continue
        phrases[k] = v.strip()

    print(f'usable chunks: {len(phrases)}')

    # merge into the main map + drop junk, then regenerate en_ui_map.g.dart
    before = len(main_map)
    for k in [k for k in main_map if is_junk(k)]:
        del main_map[k]
    dropped = before - len(main_map)
    added = 0
    for k, v in phrases.items():
        if k not in main_map:
            main_map[k] = v
            added += 1
    json.dump(main_map, open(MAIN_JSON, 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print(f'en_ui_map.json: dropped {dropped} junk, added {added}, '
          f'total {len(main_map)}')

    gen = os.path.join(HERE, 'generate_en_ui_map_dart.py')
    subprocess.run([sys.executable, gen], check=True)


if __name__ == '__main__':
    main()
