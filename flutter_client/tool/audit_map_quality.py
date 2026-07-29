"""Find kEnUiMap entries whose English value is still Vietnamese (failed translation)."""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DART = os.path.join(os.path.dirname(HERE), 'lib', 'l10n', 'en_ui_map.g.dart')

VN = re.compile(r'[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]')

# Vietnamese words without diacritics that still signal untranslated text
VN_WORDS = re.compile(
    r'\b(cua|khong|nhan|vien|luong|cong|thang|ngay|gio|phep|tao|xoa|sua|luu|'
    r'chon|tim|kiem|bang|danh|sach|thong|tin|bao|cao|cai|dat|nhap|xuat|'
    r'va|hoac|voi|cho|tai|khoan|don|hang|kho|ban|mua|tien|thu|chi)\b',
    re.IGNORECASE)

src = open(DART, encoding='utf-8').read()
pairs = re.findall(r"^\s*r?'((?:[^'\\]|\\.)*)':\s*r?'((?:[^'\\]|\\.)*)',\s*$",
                   src, re.M)
print('map entries parsed:', len(pairs))

bad = []
for k, v in pairs:
    if VN.search(v):
        bad.append((k, v, 'diacritic'))
    elif k == v and VN_WORDS.search(v) and len(v) > 3:
        bad.append((k, v, 'identical'))
    elif k == v and len(v.split()) >= 2:
        bad.append((k, v, 'identical'))

print('entries still Vietnamese:', len(bad))
limit = int(sys.argv[1]) if len(sys.argv) > 1 else 30
for k, v, why in bad[:limit]:
    print(f'[{why}] {k}  ->  {v}')

out = os.path.join(HERE, 'untranslated.json')
with open(out, 'w', encoding='utf-8') as f:
    json.dump([k for k, _v, _w in bad], f, ensure_ascii=False, indent=1)
print('wrote', out)
