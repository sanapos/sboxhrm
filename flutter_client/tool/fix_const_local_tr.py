#!/usr/bin/env python3
"""Remove 'const ' before local const declarations / constructors that contain tr(."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"

# const name = Widget( ... tr(
PAT_LOCAL = re.compile(
    r"\bconst\s+([a-zA-Z_][\w]*)\s*=\s*",
)
TR_CALL = re.compile(r"(?<![\w.$])trN?\(")


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
        # Remove const from: const foo = <anything with tr before ;>
        for m in reversed(list(PAT_LOCAL.finditer(out))):
            # look ahead until semicolon at depth 0
            i = m.end()
            depth = 0
            in_str = None
            esc = False
            j = i
            while j < len(out):
                c = out[j]
                if in_str:
                    if esc:
                        esc = False
                    elif c == "\\":
                        esc = True
                    elif c == in_str:
                        in_str = None
                else:
                    if c in ("'", '"'):
                        in_str = c
                    elif c in "({[":
                        depth += 1
                    elif c in ")}]":
                        depth -= 1
                    elif c == ";" and depth <= 0:
                        chunk = out[m.start() : j]
                        if TR_CALL.search(chunk):
                            # remove const 
                            out = out[: m.start()] + out[m.start() + 6 :]
                            removed += 1
                        break
                j += 1
        if removed:
            p.write_text(out, encoding="utf-8")
            files += 1
            total += removed
            print(f"{p.relative_to(ROOT)} removed={removed}")
    print(f"files={files} total={total}")


if __name__ == "__main__":
    main()
