"""Extract Vietnamese literal chunks from dynamic tr() templates that tr() still misses."""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), 'lib')
DART = os.path.join(LIB, 'l10n', 'en_ui_map.g.dart')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

src = open(DART, encoding='utf-8').read()
MAP = dict(re.findall(
    r"^\s*r?'((?:[^'\\]|\\.)*)':\s*r?'((?:[^'\\]|\\.)*)',\s*$", src, re.M))

EXPR = re.compile(
    r'\$\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}|\$[A-Za-z_][A-Za-z0-9_]*')
# Escape sequences and quotes delimit chunks, but only after ${...} is removed —
# interpolations legitimately contain double quotes, e.g. ${req["name"]}.
DELIM = re.compile(r'\\n|\\t|"|«|»')
STRIP = ' \t:·•|/()[]-—,.?!%"«»\n'

# Every VN literal with no exact map entry, wherever it sits in the source —
# the full chunk universe. literal_misses.json also covers strings held in data
# classes (NavItem.subtitle, catalog labels) that never appear inside tr('...').
templates = json.load(
    open(os.path.join(HERE, 'literal_misses.json'), encoding='utf-8'))

chunks = {}
for t in templates:
    for part in DELIM.split(EXPR.sub('\x00', t)):
        for c in part.split('\x00'):
            # also split on inner separators that are never part of a phrase
            for piece in re.split(r'\s*[·•|]\s*|\s—\s', c.strip(STRIP)):
                piece = piece.strip(STRIP)
                if len(piece) < 2 or not VN.search(piece):
                    continue
                chunks[piece] = MAP.get(piece, '')

# Fragments of a cut interpolation, of HTML, or of a regex are never UI copy.
JUNK = re.compile(r'[{}]|</|\)\.format\(|\\[sSdDwWbBpP]|^[ìíịỉĩỳýỵỷỹàáảãạ]+$')


def is_junk(s):
    if JUNK.search(s):
        return True
    # The alphabet constants used for diacritic stripping are code data, not copy;
    # real UI text this long always contains a space.
    return len(s) > 20 and not re.search(r'\s', s)


chunks = {k: v for k, v in chunks.items() if not is_junk(k)}

have = {k: v for k, v in chunks.items() if v}
need = sorted([k for k, v in chunks.items() if not v], key=len)

print('distinct VN chunks:', len(chunks))
print('  already in map  :', len(have))
print('  need translation:', len(need))
for s in need[:40]:
    print('   -', s)

with open(os.path.join(HERE, 'chunks_need.json'), 'w', encoding='utf-8') as f:
    json.dump(need, f, ensure_ascii=False, indent=1)

# Accumulate every chunk ever seen; each pass only sees the current residual.
ALL = os.path.join(HERE, 'chunks_all.json')
known = set(json.load(open(ALL, encoding='utf-8'))) if os.path.exists(ALL) else set()
known.update(chunks.keys())
with open(ALL, 'w', encoding='utf-8') as f:
    json.dump(sorted(known), f, ensure_ascii=False, indent=1)
print(f'wrote tool/chunks_need.json, tool/chunks_all.json ({len(known)} total)')
