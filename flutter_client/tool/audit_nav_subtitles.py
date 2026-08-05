"""Check the home-screen feature notes (NavItem.subtitle) resolve to English."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), 'lib')
sys.path.insert(0, HERE)
import simulate_tr as S  # noqa: E402

FIELD = re.compile(r"(?:subtitle|label|title|hint|desc)\s*:\s*'((?:[^'\\]|\\.)*)'")

files = [os.path.join(LIB, 'screens', 'main_layout.dart'),
         os.path.join(LIB, 'screens', 'dashboard_screen.dart')]

for p in files:
    src = open(p, encoding='utf-8').read()
    found = FIELD.findall(src)
    vn = [s for s in found if S.VN.search(s)]
    bad = []
    for s in vn:
        out = S.tr(S.render(s))
        if S.VN.search(re.sub(r'(?<![^\W\d_])đ(?![^\W\d_])', '', out, flags=re.I)):
            bad.append((s, out))
    print(f'{os.path.basename(p)}: {len(found)} labels, {len(vn)} Vietnamese, '
          f'{len(bad)} still Vietnamese after tr()')
    for s, out in bad[:10]:
        print(f'   MISS {s[:70]!r} -> {out[:70]!r}')
    for s in vn[:3]:
        print(f'   ok   {s[:52]!r} -> {S.tr(S.render(s))[:52]!r}')
