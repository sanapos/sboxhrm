"""Vietnamese messages the API returns to the client, and whether tr() can translate them.

The Flutter map is built from Dart sources only, so server-side copy shows up in
snackbars/notifications untranslated unless it is added here too.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
API = os.path.join(REPO, 'src')
DART = os.path.join(os.path.dirname(HERE), 'lib', 'l10n', 'en_ui_map.g.dart')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

src = open(DART, encoding='utf-8').read()
KEYS = set(k for k, _v in re.findall(
    r"^\s*r?'((?:[^'\\]|\\.)*)':\s*r?'((?:[^'\\]|\\.)*)',\s*$", src, re.M))

# strings handed back to callers as user-facing copy
SINKS = re.compile(
    r'(?:BadRequest|NotFound|Conflict|Unauthorized|Forbid|Fail|Error|Problem'
    r'|Message|Title|Description|Reason)\s*[(=]\s*\$?"((?:[^"\\]|\\.)*)"')

found, missing = {}, {}
for dirpath, _d, filenames in os.walk(API):
    if any(p in dirpath for p in ('obj', 'bin')):
        continue
    for fn in filenames:
        if not fn.endswith('.cs'):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, API)
        if 'SampleData' in rel:      # seed data, never shown as a notification
            continue
        try:
            text = open(p, encoding='utf-8').read()
        except Exception:
            continue
        for m in SINKS.finditer(text):
            s = m.group(1).strip()
            if len(s) < 4 or not VN.search(s):
                continue
            (found if s in KEYS else missing)[s] = rel

print('backend VN messages already in map:', len(found))
print('backend VN messages missing       :', len(missing))
limit = int(sys.argv[1]) if len(sys.argv) > 1 else 25
for i, (s, rel) in enumerate(missing.items()):
    if i >= limit:
        break
    print(f'{rel} | {s[:80]}')

with open(os.path.join(HERE, 'backend_misses.json'), 'w', encoding='utf-8') as f:
    json.dump(sorted(missing.keys()), f, ensure_ascii=False, indent=1)
print('wrote tool/backend_misses.json')
