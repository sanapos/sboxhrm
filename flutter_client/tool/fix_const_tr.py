#!/usr/bin/env python3
"""Remove const before constructors whose argument tree contains tr(...)."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
CONST_CALL = re.compile(
    r"\bconst\s+([A-Z][A-Za-z0-9_]*"          # ClassName
    r"(?:\.[A-Za-z0-9_]+)?"                    # .namedConstructor
    r"(?:<[^<>()]*(?:<[^<>()]*>[^<>()]*)*>)?"  # <Generic<Args>>
    r")\s*\("
)


def matching_paren_end(text: str, open_idx: int) -> int:
    """open_idx points at '('; return index of matching ')'."""
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
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def process(text: str) -> tuple[str, int]:
    removed = 0
    # Work from end so indices stay valid
    matches = list(CONST_CALL.finditer(text))
    for m in reversed(matches):
        open_paren = m.end() - 1
        end = matching_paren_end(text, open_paren)
        if end < 0:
            continue
        body = text[open_paren : end + 1]
        if "tr(" not in body:
            continue
        text = text[: m.start()] + text[m.start(1) :]
        removed += 1
    return text, removed


def main() -> None:
    files = 0
    total = 0
    for p in sorted(ROOT.rglob("*.dart")):
        if "l10n" in p.parts:
            continue
        original = p.read_text(encoding="utf-8")
        if "tr(" not in original or "const " not in original:
            continue
        new, n = process(original)
        if n:
            p.write_text(new, encoding="utf-8")
            files += 1
            total += n
            print(f"{p.relative_to(ROOT)} removed_const={n}")
    print(f"files={files} removed_const_total={total}")


if __name__ == "__main__":
    main()
