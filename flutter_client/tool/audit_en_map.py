#!/usr/bin/env python3
"""Audit EN map quality + remaining un-wrapped Vietnamese UI strings."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LIB = ROOT.parent / "lib"
VN = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)

data = json.loads((ROOT / "en_ui_map.json").read_text(encoding="utf-8"))
same = {k: v for k, v in data.items() if k == v}
still_vn = {k: v for k, v in data.items() if k != v and VN.search(v)}
good = len(data) - len(same) - len(still_vn)

print(f"map_entries={len(data)}")
print(f"  translated_ok={good}")
print(f"  identical_untranslated={len(same)}")
print(f"  value_still_vietnamese={len(still_vn)}")

counts = {}
vn_src = json.loads((ROOT / "vn_strings.json").read_text(encoding="utf-8"))
for item in vn_src:
    counts[item["vi"]] = item["count"]

bad = sorted(
    ((counts.get(k, 0), k) for k in list(same) + list(still_vn)),
    reverse=True,
)
print("\nTop untranslated by usage:")
for c, s in bad[:40]:
    print(f"  {c}\t{s[:70]}")

print("\n--- Unwrapped VN literal patterns in lib/ ---")
PATTERNS = {
    "Tab(text:": re.compile(r"Tab\(\s*text:\s*'([^']*)'"),
    "label:": re.compile(r"(?<!\w)label:\s*'([^']*)'"),
    "title:'": re.compile(r"(?<!\w)title:\s*'([^']*)'"),
    "TextSpan(text:": re.compile(r"TextSpan\(\s*text:\s*'([^']*)'"),
    "SelectableText(": re.compile(r"SelectableText\(\s*'([^']*)'"),
    "string list item": re.compile(r"^\s*'([^']{2,60})',\s*$", re.M),
    "return 'vi'": re.compile(r"return\s+'([^']{2,80})';"),
    "?? 'vi'": re.compile(r"\?\?\s*'([^']{2,60})'"),
    "ternary 'vi'": re.compile(r"\?\s*'([^']{2,60})'\s*:"),
    "var = 'vi'": re.compile(r"=\s*'([^']{3,80})';"),
}
totals = {k: 0 for k in PATTERNS}
for p in LIB.rglob("*.dart"):
    if "l10n" in p.parts:
        continue
    t = p.read_text(encoding="utf-8", errors="ignore")
    for name, pat in PATTERNS.items():
        for m in pat.finditer(t):
            if VN.search(m.group(1)):
                totals[name] += 1
for name, n in sorted(totals.items(), key=lambda x: -x[1]):
    print(f"  {name:20s} {n}")
