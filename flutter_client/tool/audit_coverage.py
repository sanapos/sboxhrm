#!/usr/bin/env python3
"""Report display sinks still not routed through tr()."""
from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dart_scan import first_arg_span  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
VN = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)
TEXT = re.compile(r"(?<![\w.$'\"])Text\s*\(")

unwrapped: Counter[str] = Counter()
by_file: Counter[str] = Counter()
for p in sorted(LIB.rglob("*.dart")):
    if "l10n" in p.parts:
        continue
    t = p.read_text(encoding="utf-8", errors="ignore")
    for m in TEXT.finditer(t):
        span = first_arg_span(t, m.end() - 1)
        if not span:
            continue
        arg = t[span[0]:span[1]].strip()
        if arg.startswith(("tr(", "trN(", "trOr(")):
            continue
        if not VN.search(arg):
            continue
        unwrapped[arg[:70]] += 1
        by_file[str(p.relative_to(LIB))] += 1

print(f"Text() with Vietnamese but no tr(): {sum(unwrapped.values())}")
for f, n in by_file.most_common(15):
    print(f"  {n}\t{f}")
print()
for s, n in unwrapped.most_common(20):
    print(f"  {n}\t{s}")

print("\n--- hardcoded vi locale in formatters ---")
LOC = re.compile(r"'vi(_VN)?'")
hits = Counter()
for p in sorted(LIB.rglob("*.dart")):
    if "l10n" in p.parts:
        continue
    t = p.read_text(encoding="utf-8", errors="ignore")
    n = len(LOC.findall(t))
    if n:
        hits[str(p.relative_to(LIB))] = n
print(f"total={sum(hits.values())} files={len(hits)}")
for f, n in hits.most_common(12):
    print(f"  {n}\t{f}")
