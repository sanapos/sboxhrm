import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB = HERE.parent / "lib"
DART = LIB / "l10n" / "en_ui_map.g.dart"
VN = re.compile(
    r"[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ"
    r"ÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]"
)
TR = re.compile(r"\btr(?:N|Or)?\(\s*'((?:[^'\\\n]|\\.)*)'")
KEY_RE = re.compile(r"^\s*r?'((?:[^'\\]|\\.)*)':", re.M)

src = DART.read_text(encoding="utf-8")
keys = set(KEY_RE.findall(src))
misses = []
for p in LIB.rglob("*.dart"):
    if p.name.endswith(".g.dart"):
        continue
    t = p.read_text(encoding="utf-8")
    for m in TR.finditer(t):
        s = m.group(1)
        if VN.search(s) and s not in keys:
            misses.append(s)
uniq = sorted(set(misses))
print(f"remaining_tr_misses {len(uniq)}")
print(f"with_dollar {sum(1 for s in uniq if '$' in s)}")
print(f"long {sum(1 for s in uniq if len(s) > 180)}")
print(f"other {sum(1 for s in uniq if '$' not in s and len(s) <= 180)}")
(HERE / "tr_misses_remaining.json").write_text(
    json.dumps(uniq, ensure_ascii=False, indent=1), encoding="utf-8"
)
