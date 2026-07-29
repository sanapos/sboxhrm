#!/usr/bin/env python3
"""Fix Text('${tr('x')}'\$\{y}') → Text('${tr('x')}${y}')."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
# File literally contains: )}'\$\{
BAD = ")}'\\$\\{"
GOOD = ")}${"


def main() -> None:
    files = 0
    total = 0
    for p in sorted(ROOT.rglob("*.dart")):
        text = p.read_text(encoding="utf-8")
        if BAD not in text:
            # also try without brace backslash
            bad2 = ")}'\\${"
            if bad2 in text:
                n = text.count(bad2)
                p.write_text(text.replace(bad2, GOOD), encoding="utf-8")
                files += 1
                total += n
                print(f"{p.relative_to(ROOT)} fixed2={n}")
            continue
        n = text.count(BAD)
        p.write_text(text.replace(BAD, GOOD), encoding="utf-8")
        files += 1
        total += n
        print(f"{p.relative_to(ROOT)} fixed={n}")
    print(f"files={files} fixed_total={total}")


if __name__ == "__main__":
    main()
