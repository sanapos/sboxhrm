"""Write a before/after sample of the mojibake repair to a UTF-8 file for review."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(REPO, 'src')
sys.path.insert(0, HERE)
from fix_mojibake import EXCLUDE, MOJI, repair_text  # noqa: E402

OUT = os.path.join(HERE, 'mojibake_preview.txt')
per_file = int(sys.argv[1]) if len(sys.argv) > 1 else 4

with open(OUT, 'w', encoding='utf-8') as out:
    for dirpath, _d, filenames in os.walk(SRC):
        if any(p in dirpath for p in (os.sep + 'obj', os.sep + 'bin')):
            continue
        for fn in sorted(filenames):
            if not fn.endswith('.cs') or fn in EXCLUDE:
                continue
            p = os.path.join(dirpath, fn)
            try:
                text = open(p, encoding='utf-8').read()
            except Exception:
                continue
            if not MOJI.search(text):
                continue
            fixed, _n = repair_text(text)
            before = text.splitlines()
            after = fixed.splitlines()
            out.write(f'=== {os.path.relpath(p, REPO)}\n')
            shown = 0
            for i, (b, a) in enumerate(zip(before, after), 1):
                if b == a:
                    continue
                out.write(f'  {i}\n    - {b.strip()[:150]}\n    + {a.strip()[:150]}\n')
                shown += 1
                if shown >= per_file:
                    break
print('wrote', OUT)
