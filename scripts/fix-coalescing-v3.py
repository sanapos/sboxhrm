#!/usr/bin/env python3
"""Undo erroneous ?? insertions from fix-coalescing-v2."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib"

REPLACEMENTS = [
    ("phơne", "phone"),
    ("Phơne", "Phone"),
    ("sê-rial", "serial"),
    ("Sê-rial", "Serial"),
    ("check-sê-rial", "check-serial"),
]

# ?? wrongly inserted before Dart keywords after ] or )
KEYWORD_FIXES = [
    (r"\]\s*\?\?\s+as\b", "] as"),
    (r"\)\s*\?\?\s+as\b", ") as"),
    (r"\]\s*\?\?\s+is\b", "] is"),
    (r"\)\s*\?\?\s+is\b", ") is"),
    (r"\]\s*\?\?\s+const\b", "] const"),
    (r"\)\s*\?\?\s+const\b", ") const"),
    (r"\?\?\s+as\s+String", "as String"),
    (r"\?\?\s+as\s+List", "as List"),
    (r"\?\?\s+as\s+Map", "as Map"),
    (r"\?\?\s+as\s+int", "as int"),
    (r"\?\?\s+as\s+double", "as double"),
    (r"\?\?\s+as\s+bool", "as bool"),
    (r"\?\?\s+as\s+dynamic", "as dynamic"),
    (r"\?\?\s+asMap\b", "asMap"),
    (r"\?\?\s+asString", "asString"),
    (r"return \[fallback\] \?\? on", "return [fallback] on"),
    (r"/// Safely run an API call; log and return \[fallback\] \?\? on",
     "/// Safely run an API call; log and return [fallback] on"),
]


def fix_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    orig = text
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    for pat, repl in KEYWORD_FIXES:
        text = re.sub(pat, repl, text)
    # property access: .phone ?? employee -> .phone ?? employee (already ok)
    # dotted chain broken: employee.phone ?? employee.employeeCode is correct
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
