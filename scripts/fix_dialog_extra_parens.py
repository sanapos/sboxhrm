#!/usr/bin/env python3
"""Fix stray '),' before actions: in files using ScrollableDialogBody.wrap."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib" / "screens"


def fix(text: str) -> str:
    patterns = [
        (
            r"(\]\),)\s*\n(\s*)\),\s*\n\2\),\s*\n\2actions:",
            r"\1\n\2),\n\2actions:",
        ),
        (
            r"(\],)\s*\n(\s*)\),\s*\n\2\),\s*\n\2actions:",
            r"\1\n\2),\n\2actions:",
        ),
        (
            r"(\],)\s*\n(\s*)\),\s*\n\2\),\s*\n\2\),\s*\n\2actions:",
            r"\1\n\2),\n\2actions:",
        ),
        (
            r"(child: \w+\(setDlgState\),)\s*\n\s*\),\s*\n\s*\),\s*\n\s*actions:",
            r"\1\n            ),\n            actions:",
        ),
    ]
    for pat, repl in patterns:
        prev = None
        while prev != text:
            prev = text
            text = re.sub(pat, repl, text)
    return text


def main():
    n = 0
    for path in sorted(ROOT.rglob("*.dart")):
        if ".bak" in path.name:
            continue
        text = path.read_text(encoding="utf-8")
        if "ScrollableDialogBody" not in text:
            continue
        fixed = fix(text)
        if fixed != text:
            path.write_text(encoding="utf-8", data=fixed)
            n += 1
            print(path.relative_to(ROOT.parent.parent.parent))
    print(f"Fixed {n} files")


if __name__ == "__main__":
    main()
