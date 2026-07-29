"""Find Vietnamese values left inside the 'en' section of app_localizations.dart."""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), 'lib', 'l10n', 'app_localizations.dart')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')
PAIR = re.compile(r"'([A-Za-z0-9_]+)'\s*:\s*'((?:[^'\\]|\\.)*)'")

src = open(SRC, encoding='utf-8').read()
i = src.find("'en':")
if i < 0:
    i = src.find("'en'")
print('en section offset:', i)
seg = src[i:]

vi_pairs = dict(PAIR.findall(src[:i]))
bad = [(k, v) for k, v in PAIR.findall(seg) if VN.search(v)]
print('VN values still in en section:', len(bad))
for k, v in bad:
    print(f'  {k} -> {v}')

en_keys = set(k for k, _ in PAIR.findall(seg))
missing = [k for k in vi_pairs if k not in en_keys]
print('keys present in vi but missing in en:', len(missing))
for k in missing[:40]:
    print(f'  {k} (vi: {vi_pairs[k][:40]})')
