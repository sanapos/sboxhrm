"""Count Text(<expression>) call sites whose argument is not a literal and not tr()-wrapped."""
import os
import re
import sys
from collections import Counter

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'lib')

# Text( followed by something that is NOT a quote and NOT tr(/trN(/trOr(
RX = re.compile(r"\bText\(\s*(?!['\"])(?!tr\()(?!trN\()(?!trOr\()(?!AppLocalizations)([A-Za-z_$][^,\n)]{0,80})")

counts = Counter()
samples = []
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
        for m in RX.finditer(src):
            counts[rel] += 1
            samples.append((rel, m.group(1).strip()))

print('Text(<expr>) not wrapped:', sum(counts.values()))
print('files:', len(counts))
for k, v in counts.most_common(15):
    print(f'  {v:4d}  {k}')
limit = int(sys.argv[1]) if len(sys.argv) > 1 else 20
print('--- samples ---')
for rel, expr in samples[:limit]:
    print(f'{rel} | {expr}')
