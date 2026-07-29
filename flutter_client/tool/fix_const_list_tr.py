#!/usr/bin/env python3
"""Remove const before list literals that contain tr(...)."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
CONST_LIST = re.compile(r"const\s*\[")


def match_bracket(text: str, open_idx: int) -> int:
    depth = 0
    i = open_idx
    in_str = None
    escape = False
    while i < len(text):
        c = text[i]
        if in_str:
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == in_str:
                in_str = None
        else:
            if c in ("'", '"'):
                in_str = c
            elif c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def main() -> None:
    files = 0
    total = 0
    for p in sorted(ROOT.rglob("*.dart")):
        if "l10n" in p.parts:
            continue
        text = p.read_text(encoding="utf-8")
        if "tr(" not in text:
            continue
        out = text
        removed = 0
        for m in reversed(list(CONST_LIST.finditer(out))):
            open_idx = m.end() - 1
            end = match_bracket(out, open_idx)
            if end < 0:
                continue
            if "tr(" not in out[open_idx : end + 1]:
                continue
            bracket = out.find("[", m.start())
            out = out[: m.start()] + out[bracket:]
            removed += 1
        if removed:
            p.write_text(out, encoding="utf-8")
            files += 1
            total += removed
            print(f"{p.relative_to(ROOT)} removed={removed}")
    print(f"files={files} removed_total={total}")


if __name__ == "__main__":
    main()
