#!/usr/bin/env python3
"""Restore Dart ?? null-coalescing broken by encoding repair (?? -> empty)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib"

FIXES: list[tuple[str, str]] = [
    ("] ''", "] ?? ''"),
    ("] '—'", "] ?? '—'"),
    ("breakMinutes 0)", "breakMinutes ?? 0)"),
    ("fromUserName '—'", "fromUserName ?? '—'"),
    ("toUserName '—'", "toUserName ?? '—'"),
    ("department ''}", "department ?? ''}"),
    ("position ''}", "position ?? ''}"),
    ("_registeredDeviceName ''", "_registeredDeviceName ?? ''"),
    ("_connectedWifiSsid ''", "_connectedWifiSsid ?? ''"),
]


def fix_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    orig = text
    for old, new in FIXES:
        text = text.replace(old, new)
    text = re.sub(r"(\[[^\]]+\]) ''\)", r"\1 ?? '')", text)
    text = re.sub(r"(\$\{[^}]+) ''(\})", r"\1 ?? ''\2", text)
    text = re.sub(r"(\w+) ''\)", r"\1 ?? '')", text)
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
