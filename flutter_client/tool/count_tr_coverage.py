#!/usr/bin/env python3
import re
from pathlib import Path

VN = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)
ROOT = Path(__file__).resolve().parents[1] / "lib"
text_tr = 0
text_vn = 0
files_tr = 0
for p in ROOT.rglob("*.dart"):
    if "l10n" in p.parts:
        continue
    t = p.read_text(encoding="utf-8", errors="ignore")
    if "Text(tr(" in t:
        files_tr += 1
    text_tr += len(re.findall(r"Text\(tr\(", t))
    for m in re.finditer(r"Text\(\s*'((?:\\.|[^'\\])*)'", t):
        if VN.search(m.group(1)):
            text_vn += 1
print("files_with_tr", files_tr)
print("Text(tr count", text_tr)
print("bare Text VN left", text_vn)
