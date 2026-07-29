"""List strings passed to tr('...') in source that have NO entry in kEnUiMap."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), 'lib')
DART = os.path.join(LIB, 'l10n', 'en_ui_map.g.dart')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

src = open(DART, encoding='utf-8').read()
keys = set(k for k, _v in re.findall(
    r"^\s*r?'((?:[^'\\]|\\.)*)':\s*r?'((?:[^'\\]|\\.)*)',\s*$", src, re.M))

TR = re.compile(r"\btr(?:N|Or)?\(\s*'((?:[^'\\\n]|\\.)*)'")

misses = {}
total = 0
for dirpath, _d, filenames in os.walk(LIB):
    for fn in filenames:
        if not fn.endswith('.dart') or fn.endswith('.g.dart'):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, LIB)
        try:
            text = open(p, encoding='utf-8').read()
        except Exception:
            continue
        for m in TR.finditer(text):
            s = m.group(1)
            if not VN.search(s):
                continue
            total += 1
            if s in keys:
                continue
            misses.setdefault(s, rel)

print('tr() VN call sites:', total)
print('distinct strings missing from map:', len(misses))
limit = int(sys.argv[1]) if len(sys.argv) > 1 else 30
for i, (s, rel) in enumerate(misses.items()):
    if i >= limit:
        break
    print(f'{rel} | {s[:90]}')

out = os.path.join(HERE, 'tr_misses.json')
with open(out, 'w', encoding='utf-8') as f:
    json.dump(sorted(misses.keys()), f, ensure_ascii=False, indent=1)
print('wrote', out)
