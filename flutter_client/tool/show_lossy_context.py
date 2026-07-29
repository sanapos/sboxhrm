"""Print source context for the ambiguous lossy tokens so they can be mapped by hand."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(REPO, 'src')
sys.path.insert(0, HERE)
from fix_mojibake import EXCLUDE, repair_text  # noqa: E402

WANTED = sys.argv[1:] or [
    'Má»i', 'Äá»', 'Ä‘á»', 'Äá»’', 'Äá»¦', 'Ã„â€˜', 'chÃ¡Â»Ân',
    'khÃ¡Â»Âi', 'thÃ¡Â»Âi', 'gÃ¡Â»Âi', 'gá»i', 'nghá»', 'bá»', 'vá»',
]

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
        fixed, _ = repair_text(text)
        for i, line in enumerate(fixed.splitlines(), 1):
            for w in WANTED:
                if w in line:
                    print(f'{os.path.relpath(p, REPO)}:{i} [{w}]')
                    print(f'   {line.strip()[:150]}')
                    break
