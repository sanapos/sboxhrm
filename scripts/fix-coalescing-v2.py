#!/usr/bin/env python3
"""Fix ?? null-coalescing broken by encoding repair (pass 2)."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib"


def fix_chain_bracket(text: str) -> str:
    """record['a'] record['b'] -> record['a'] ?? record['b']"""
    prev = None
    while prev != text:
        prev = text
        text = re.sub(r"(?<!\?\?)(\[[^\]]+\])\s+(\[)", r"\1 ?? \2", text)
        text = re.sub(
            r"(?<!\?\?)(\[[^\]]+\])\s+([a-zA-Z_][a-zA-Z0-9_]*)",
            r"\1 ?? \2",
            text,
        )
        text = re.sub(r"(?<!\?\?)(\[[^\]]+\])\s+'", r"\1 ?? '", text)
    return text


def fix_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    orig = text

    # Ternary false branch wrongly got ??
    text = text.replace(": ?? ''", ": ''")

    text = fix_chain_bracket(text)

    # Map / json value: 'key': var ''
    text = re.sub(
        r"(:\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s+''",
        r"\1\2 ?? ''",
        text,
    )

    # Assignment: id = departmentId ''
    text = re.sub(
        r"(=\s*)([a-zA-Z_][a-zA-Z0-9_.]*)\s+''(\s*[;,)])",
        r"\1\2 ?? ''\3",
        text,
    )

    # Property / nullable: user.department '', loc?.name ''
    text = re.sub(
        r"(?<!\?\?)(?<![:\w])([a-zA-Z_][\w.?]*)\s+''",
        lambda m: m.group(0)
        if m.group(1) in ("return", "break", "continue", "throw")
        else f"{m.group(1)} ?? ''",
        text,
    )

    # json.encode inline: reason ''} -> reason ?? ''}
    text = re.sub(
        r"(\w+)\s+''(\s*\}\))",
        r"\1 ?? ''\2",
        text,
    )

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
