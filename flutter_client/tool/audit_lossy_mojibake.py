"""List the mojibake tokens left after the reversible repair, with counts.

These lost a byte that cp1252 cannot represent (0x81, 0x8D, 0x8F, 0x90, 0x9D),
so "ề", "ọ", "ỏ", "ờ", "Ố" and "Đ" cannot be reconstructed by decoding — they
need a word-level table.
"""
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(REPO, 'src')
sys.path.insert(0, HERE)
from fix_mojibake import MOJI, EXCLUDE, repair_text  # noqa: E402

TOKEN = re.compile(r'\S*(?:Ã[\u0080-\u00ff]|á»|áº|Ä|Æ°|â€)\S*')

counts = Counter()
for dirpath, _d, filenames in os.walk(SRC):
    if any(p in dirpath for p in (os.sep + 'obj', os.sep + 'bin')):
        continue
    for fn in filenames:
        if not fn.endswith('.cs') or fn in EXCLUDE:
            continue
        p = os.path.join(dirpath, fn)
        try:
            text = open(p, encoding='utf-8').read()
        except Exception:
            continue
        if not MOJI.search(text):
            continue
        fixed, _ = repair_text(text)
        for m in TOKEN.finditer(fixed):
            counts[m.group(0).strip('.,;:()[]{}"\'')] += 1

print('distinct broken tokens:', len(counts), ' occurrences:', sum(counts.values()))
limit = int(sys.argv[1]) if len(sys.argv) > 1 else 60
for tok, n in counts.most_common(limit):
    print(f'{n:5d}  {tok}')

json.dump({k: '' for k, _ in counts.most_common()},
          open(os.path.join(HERE, 'lossy_tokens.json'), 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
print('wrote tool/lossy_tokens.json')
