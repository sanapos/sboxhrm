#!/usr/bin/env python3
"""Fix tr('a') 'b' adjacent string concat → tr('a' 'b') then merge, or tr('a') + tr('b')."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"

# tr('...')\n?    '...'  (adjacent string after tr call)
PAT = re.compile(
    r"tr\(\s*'((?:\\.|[^'\\])*)'\s*\)\s*\n?\s*'((?:\\.|[^'\\])*)'"
)


def repl(m: re.Match[str]) -> str:
    a, b = m.group(1), m.group(2)
    return f"tr('{a}{b}')"


def main() -> None:
    files = 0
    total = 0
    for p in sorted(ROOT.rglob("*.dart")):
        if "l10n" in p.parts:
            continue
        text = p.read_text(encoding="utf-8")
        new, n = PAT.subn(repl, text)
        # also double-quoted second part
        new2, n2 = re.subn(
            r'tr\(\s*\'((?:\\.|[^\'\\])*)\'\s*\)\s*\n?\s*"((?:\\.|[^"\\])*)"',
            lambda m: f"tr('{m.group(1)}{m.group(2)}')",
            new,
        )
        n += n2
        new = new2
        if not n:
            continue
        p.write_text(new, encoding="utf-8")
        files += 1
        total += n
        print(f"{p.relative_to(ROOT)} n={n}")
    print(f"files={files} total={total}")


if __name__ == "__main__":
    main()
