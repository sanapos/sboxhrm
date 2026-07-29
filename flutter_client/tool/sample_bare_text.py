#!/usr/bin/env python3
import re
from pathlib import Path

VN = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)
ROOT = Path(__file__).resolve().parents[1] / "lib"
samples = []
for p in ROOT.rglob("*.dart"):
    if "l10n" in p.parts:
        continue
    t = p.read_text(encoding="utf-8", errors="ignore")
    for m in re.finditer(r"Text\(\s*'((?:\\.|[^'\\])*)'", t):
        start = m.start()
        prev = t[max(0, start - 6) : start]
        if prev.endswith("tr("):
            continue
        if not VN.search(m.group(1)):
            continue
        samples.append((str(p.relative_to(ROOT)), m.group(1)[:70]))
        if len(samples) >= 20:
            break
    if len(samples) >= 20:
        break
for path, s in samples:
    print(f"{path} | {s!r}")
print("shown", len(samples))
