"""Show which tr() path handles a string and what blocks a full translation."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import simulate_tr as S  # noqa: E402

SAMPLES = [
    'Xóa chấm công$punch lúc $t ngày $dateStr — $nv.',
    'Bổ sung chấm công$punch lúc $t ngày $dateStr — $nv.',
    '${prefix}Còn $remaining ngày',
    '${diff.inSeconds}s trước',
    'Nghỉ$suffix',
    '$startStr · 1 ngày$halfNote',
]

for raw in sys.argv[1:] or SAMPLES:
    r = S.render(raw)
    print(f'\ninput : {raw}')
    print(f'render: {r}')
    print(f'tr()  : {S.tr(r)}')
    frag = S.replace_fragments(r)
    print(f'fragments: {frag!r}')
    if frag is None:
        # Show what fragment substitution produces before the all-or-nothing gate.
        out = r
        for vi, en in S.PHRASES:
            i = out.find(vi)
            while i >= 0:
                end = i + len(vi)
                if ((i == 0 or not S.WORD.match(out[i - 1]))
                        and (end >= len(out) or not S.WORD.match(out[end]))):
                    out = out[:i] + en + out[end:]
                    i = out.find(vi, i + len(en))
                else:
                    i = out.find(vi, i + 1)
        print(f'  partial : {out!r}')
        probe = re.sub(r'(?<![^\W\d_])đ(?![^\W\d_])', '', out, flags=re.I)
        left = set(re.findall(r'\S*' + S.VN.pattern + r'\S*', probe))
        print(f'  blocked by: {sorted(left)}')
