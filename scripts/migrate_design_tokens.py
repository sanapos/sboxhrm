#!/usr/bin/env python3
"""Migrate legacy colors / breakpoints toward App Design System."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(r"E:/SBOX CURSOR/ZKTecoADMS-master/flutter_client/lib")


def ensure_import(text: str, path: Path) -> str:
    if "AppColors." not in text:
        return text
    if "design_system/design_system.dart" in text:
        return text
    depth = len(path.relative_to(ROOT).parts) - 1
    imp = "import '" + ("../" * depth) + "design_system/design_system.dart';"
    lines = text.splitlines(True)
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            insert_at = i + 1
        elif insert_at and not line.startswith("import "):
            break
    lines.insert(insert_at, imp + "\n")
    return "".join(lines)


def main() -> None:
    changed: list[str] = []
    for path in ROOT.rglob("*.dart"):
        if "design_system" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        orig = text
        text = text.replace("Color(0xFF0C56D0)", "AppColors.primary")
        text = text.replace("Color(0xFF0c56d0)", "AppColors.primary")
        text = re.sub(r"\bColors\.blue\b(?!Grey|Accent)", "AppColors.info", text)
        text = re.sub(r"(width|maxWidth)\s*<\s*600\b", r"\1 < 768", text)
        text = re.sub(r"(width|maxWidth)\s*<=\s*600\b", r"\1 <= 768", text)
        text = re.sub(r"size\.width\s*<\s*600\b", "size.width < 768", text)
        if text == orig:
            continue
        text = ensure_import(text, path)
        path.write_text(text, encoding="utf-8")
        changed.append(str(path.relative_to(ROOT)))
    print(f"updated {len(changed)} files")
    for c in changed:
        print(c)


if __name__ == "__main__":
    main()
