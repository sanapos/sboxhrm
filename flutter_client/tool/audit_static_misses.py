"""Static (non-interpolated) Vietnamese literals with no en_ui_map entry."""
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), 'lib')

miss = json.load(open(os.path.join(HERE, 'literal_misses.json'), encoding='utf-8'))

# Drop interpolated templates and regex/code fragments — handled elsewhere.
BAD = re.compile(r'[$\\]|\(\?|\p{L}' if False else r'[$\\]|\(\?')
static = [s for s in miss if not BAD.search(s)]
print('static VN literals missing from map:', len(static), 'of', len(miss))

# where does each one live?
where = {}
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
        for s in static:
            if s not in where and s in text:
                where[s] = rel

counts = Counter(where.values())
print('--- worst files ---')
for f, c in counts.most_common(15):
    print(f'  {c:4d}  {f}')

focus = sys.argv[1] if len(sys.argv) > 1 else None
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 40
print('--- samples ---')
shown = 0
for s in static:
    rel = where.get(s, '?')
    if focus and focus not in rel:
        continue
    print(f'{rel} | {s[:90]}')
    shown += 1
    if shown >= limit:
        break

with open(os.path.join(HERE, 'static_misses.json'), 'w', encoding='utf-8') as f:
    json.dump(static, f, ensure_ascii=False, indent=1)
print('wrote tool/static_misses.json')
