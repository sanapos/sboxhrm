"""Report which constructor/callee owns each bare-VN named param (title/label/subtitle...)."""
import os
import re
import sys
from collections import Counter

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'lib')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]')

PARAMS = ['title', 'label', 'subtitle', 'message', 'text', 'name', 'description']
param_re = re.compile(r'\b(' + '|'.join(PARAMS) + r")\s*:\s*'((?:[^'\\\n]|\\.)*)'")

ident_re = re.compile(r'([A-Za-z_$][A-Za-z0-9_$]*)\s*\(\s*$')


def owner_of(src, idx):
    """Walk backwards from idx to the opening '(' of the enclosing arg list."""
    depth = 0
    i = idx
    while i > 0:
        c = src[i]
        if c in ')]}':
            depth += 1
        elif c in '([{':
            if depth == 0:
                if c == '(':
                    m = ident_re.search(src[max(0, i - 60):i + 1])
                    return m.group(1) if m else '?'
                return '?'
            depth -= 1
        i -= 1
    return '?'


counts = Counter()
by_owner = {}

for dirpath, _d, filenames in os.walk(ROOT):
    for fn in filenames:
        if not fn.endswith('.dart') or fn.endswith('.g.dart'):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, ROOT)
        try:
            src = open(p, encoding='utf-8').read()
        except Exception:
            continue
        for m in param_re.finditer(src):
            if not VN.search(m.group(2)):
                continue
            own = owner_of(src, m.start() - 1)
            key = f'{own}.{m.group(1)}'
            counts[key] += 1
            by_owner.setdefault(key, []).append((rel, m.group(2)[:50]))

print('total', sum(counts.values()))
top = int(sys.argv[1]) if len(sys.argv) > 1 else 40
for k, v in counts.most_common(top):
    ex = by_owner[k][0]
    print(f'{v:5d}  {k:42s} e.g. {ex[0]} | {ex[1]}')
