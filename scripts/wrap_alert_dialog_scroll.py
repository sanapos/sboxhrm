#!/usr/bin/env python3
"""Wrap AlertDialog content: Column(mainAxisSize: min) with ScrollableDialogBody."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib" / "screens"


def rel_import(path: Path) -> str:
    rel = path.relative_to(ROOT.parent)
    depth = len(rel.parts) - 1
    return "../" * depth + "widgets/scrollable_dialog_body.dart"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def fix_file(path: Path) -> bool:
    text = read_text(path)
    if "AlertDialog" not in text or "content: Column(" not in text:
        return False
    orig = text
    imp = rel_import(path)
    if "scrollable_dialog_body" not in text:
        anchor = "import 'package:flutter/material.dart';"
        if anchor in text:
            text = text.replace(
                anchor, anchor + f"\nimport '{imp}';", 1
            )
    text = re.sub(
        r"content: Column\(\s*\n(\s*)mainAxisSize: MainAxisSize\.min,",
        r"content: ScrollableDialogBody.forAlert(context, Column(\n\1mainAxisSize: MainAxisSize.min,",
        text,
    )
    text = re.sub(
        r"content: Column\(mainAxisSize: MainAxisSize\.min,",
        r"content: ScrollableDialogBody.forAlert(context, Column(mainAxisSize: MainAxisSize.min,",
        text,
    )
    # Close forAlert before actions: ),\n          actions: -> )),\n          actions:
    text = re.sub(
        r"(ScrollableDialogBody\.forAlert\(context, child: Column\([\s\S]*?)\n(\s*)\),\n(\s*)actions:",
        lambda m: m.group(1) + "\n" + m.group(2) + ")),\n" + m.group(3) + "actions:",
        text,
    )
    text = text.replace("actions:actions:", "actions:")
    if text != orig:
        path.write_text(encoding="utf-8", data=text)
        return True
    return False


def main():
    changed = []
    for path in sorted(ROOT.rglob("*.dart")):
        if ".bak" in path.name:
            continue
        if fix_file(path):
            changed.append(path)
    print(f"Updated {len(changed)} files")
    for p in changed:
        print(p.relative_to(ROOT.parent.parent.parent))


if __name__ == "__main__":
    main()
