#!/usr/bin/env python3
"""Restore ?? removed by fix-coalescing-v2 property regex."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib"

LITERAL_REPLACEMENTS = [
    ("MobileAttendanceSettingsẽ", "MobileAttendanceSettings?"),
    ("số.toString()", "s.toString()"),
    ("readAt DateTime", "readAt ?? DateTime"),
    ("_effectiveDate _selectedDate", "_effectiveDate ?? _selectedDate"),
    ("_selectedDate DateTime", "_selectedDate ?? DateTime"),
    ("['quantity'] 1", "['quantity'] ?? 1"),
]


def fix_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    orig = text
    for old, new in LITERAL_REPLACEMENTS:
        text = text.replace(old, new)

    text = re.sub(r"\?\.toString\(\)\s+''", "?.toString() ?? ''", text)
    text = re.sub(r"\?\.toString\(\)\s+'0'", "?.toString() ?? '0'", text)
    text = re.sub(r"\.toString\(\)\s+''", ".toString() ?? ''", text)
    text = re.sub(r"\.toString\(\)\s+'0'", ".toString() ?? '0'", text)
    text = re.sub(r"\.toLowerCase\(\)\s+''", ".toLowerCase() ?? ''", text)
    text = re.sub(
        r"\.toString\(\)\s+([a-zA-Z_\[])",
        r".toString() ?? \1",
        text,
    )
    text = re.sub(r"double\.tryParse\(([^)]+)\)\s+0", r"double.tryParse(\1) ?? 0", text)
    text = re.sub(r"int\.tryParse\(([^)]+)\)\s+0", r"int.tryParse(\1) ?? 0", text)
    text = re.sub(r"as List\?\)\s+\[\]", "as List?) ?? []", text)
    text = re.sub(r"as num\?\)\s+0", "as num?) ?? 0", text)
    text = re.sub(r"getString\(([^)]+)\)\s+''", r"getString(\1) ?? ''", text)
    text = re.sub(r"\['penaltyTier'\]\s+1", "['penaltyTier'] ?? 1", text)
    text = re.sub(
        r"int\.tryParse\(v\?\.toString\(\)\s+'0'\)\s+0",
        "int.tryParse(v?.toString() ?? '0') ?? 0",
        text,
    )
    text = re.sub(r"\?\.toInt\(\)\s+0", "?.toInt() ?? 0", text)
    text = re.sub(r"\?\.toDouble\(\)\s+0", "?.toDouble() ?? 0", text)
    text = re.sub(r"int\.tryParse\(v\.toString\(\)\)\s+0", "int.tryParse(v.toString()) ?? 0", text)
    text = re.sub(r"\)\s+0;", ") ?? 0;", text)
    text = re.sub(r"_settingsố", "_settings?.", text)
    text = re.sub(r"settingsố", "settings?.", text)
    text = re.sub(r"\.enableFaceId\s+false", ".enableFaceId ?? false", text)
    text = re.sub(r"\.enableFaceId\s+true", ".enableFaceId ?? true", text)
    text = re.sub(r"\.enableGps\s+true", ".enableGps ?? true", text)
    text = re.sub(r"\.enableWifi\s+false", ".enableWifi ?? false", text)
    text = re.sub(r"\.verificationMode\s+'all'", ".verificationMode ?? 'all'", text)
    text = re.sub(r"v\?\.toString\(\)\s+'0'\)", "v?.toString() ?? '0')", text)
    text = re.sub(r"\.text\)\s+0", ".text) ?? 0", text)
    text = re.sub(r"compareTo\(([^)]+)\s+''\)", r"compareTo(\1 ?? '')", text)

    if text != orig:
        path.write_text(text, encoding="utf-8", newline="\n")
        return True
    return False


def main() -> int:
    n = 0
    for p in sorted(ROOT.rglob("*.dart")):
        if fix_file(p):
            n += 1
            print(p.relative_to(ROOT.parent.parent))
    print(f"fixed {n} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
