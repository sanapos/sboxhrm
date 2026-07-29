"""Audit remaining bare Vietnamese literals in UI-facing named params / widgets."""
import os
import re
import sys
from collections import Counter

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'lib')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

# named params whose value is user-visible text
PARAMS = [
    'hintText', 'labelText', 'helperText', 'errorText', 'prefixText', 'suffixText',
    'counterText', 'semanticLabel', 'tooltip', 'message', 'label', 'title', 'subtitle',
    'text', 'confirmText', 'cancelText', 'helpText', 'errorFormatText',
    'errorInvalidText', 'fieldLabelText', 'fieldHintText', 'saveText',
]

# Widget(  'literal'  ) positional
POSITIONAL = ['SelectableText', 'Tab', 'Tooltip']

param_re = re.compile(
    r'\b(' + '|'.join(PARAMS) + r")\s*:\s*'((?:[^'\\\n]|\\.)*)'"
)
pos_re = re.compile(
    r'\b(' + '|'.join(POSITIONAL) + r")\(\s*'((?:[^'\\\n]|\\.)*)'"
)

counts = Counter()
samples = []

for dirpath, _dirnames, filenames in os.walk(ROOT):
    for fn in filenames:
        if not fn.endswith('.dart'):
            continue
        if fn.endswith('.g.dart'):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, ROOT)
        try:
            src = open(p, encoding='utf-8').read()
        except Exception:
            continue
        for rx in (param_re, pos_re):
            for m in rx.finditer(src):
                val = m.group(2)
                if not VN.search(val):
                    continue
                counts[m.group(1)] += 1
                samples.append((rel, m.group(1), val[:60]))

total = sum(counts.values())
print('bare VN in named params/widgets:', total)
for k, v in counts.most_common():
    print(f'  {k}: {v}')

limit = int(sys.argv[1]) if len(sys.argv) > 1 else 25
print('--- samples ---')
for rel, k, val in samples[:limit]:
    print(f'{rel} | {k} | {val}')
