"""Every Vietnamese literal in lib/ — is it present in en_ui_map, wherever it sits?

Covers strings that never appear inside tr('...') because they are stored in data
classes (NavItem.subtitle, catalog labels) and translated at the render site.
"""
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), 'lib')
DART = os.path.join(LIB, 'l10n', 'en_ui_map.g.dart')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

src = open(DART, encoding='utf-8').read()
KEYS = set(k for k, _v in re.findall(
    r"^\s*r?'((?:[^'\\]|\\.)*)':\s*r?'((?:[^'\\]|\\.)*)',\s*$", src, re.M))

SQ = re.compile(r"'((?:[^'\\\n]|\\.)*)'")
DQ = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

SKIP_FILES = ('en_ui_map.g.dart', 'app_localizations.dart')

missing = {}
present = 0
by_file = Counter()

for dirpath, _d, filenames in os.walk(LIB):
    for fn in filenames:
        if not fn.endswith('.dart') or fn in SKIP_FILES:
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, LIB)
        try:
            text = open(p, encoding='utf-8').read()
        except Exception:
            continue
        for rx in (SQ, DQ):
            for m in rx.finditer(text):
                s = m.group(1)
                if not VN.search(s) or len(s) < 2:
                    continue
                if s in KEYS:
                    present += 1
                    continue
                missing.setdefault(s, rel)
                by_file[rel] += 1

print('VN literals found in map      :', present)
print('distinct VN literals NOT in map:', len(missing))
print('--- worst files ---')
for f, c in by_file.most_common(15):
    print(f'  {c:4d}  {f}')

limit = int(sys.argv[1]) if len(sys.argv) > 1 else 25
print('--- samples ---')
for i, (s, rel) in enumerate(missing.items()):
    if i >= limit:
        break
    print(f'{rel} | {s[:80]}')

with open(os.path.join(HERE, 'literal_misses.json'), 'w', encoding='utf-8') as f:
    json.dump(sorted(missing.keys()), f, ensure_ascii=False, indent=1)
print('wrote tool/literal_misses.json')
