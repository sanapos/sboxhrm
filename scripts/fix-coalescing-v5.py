#!/usr/bin/env python3
"""Fix remaining ?? corruption patterns."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib"

REPLACEMENTS = [
    ("return ''';", "return '';"),
    ("EdgeInsetsẽ", "EdgeInsets?"),
    ("_statisticsố", "_statistics?"),
    ("số['", "s?['"),
    ("_currentLat _kDefaultLat", "_currentLat ?? _kDefaultLat"),
    ("_currentLng _kDefaultLng", "_currentLng ?? _kDefaultLng"),
    ("lat _currentLat _kDefaultLat", "lat ?? _currentLat ?? _kDefaultLat"),
]

REGEX = [
    (r"\['([^']+)'\]\s+0\}", r"['\1'] ?? 0}"),
    (r"\['([^']+)'\]\s+0,", r"['\1'] ?? 0,"),
    (r"\['([^']+)'\]\s+0'", r"['\1'] ?? 0'"),
]


def fix_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    orig = text
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    for pat, repl in REGEX:
        text = re.sub(pat, repl, text)
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
