#!/usr/bin/env python3
"""
Wrap Vietnamese *display* string literals with tr('...').

Safe patterns only (UI constructors). Skips comparisons / switch cases / map keys
used as logic, and skips lib/l10n generated sources.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
VN = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)

# Capture UI string slots: Text('...'), hintText: '...', etc.
PATTERNS = [
    # const Text('...') / Text('...')
    (
        re.compile(r"\bconst\s+Text\(\s*'((?:\\.|[^'\\])*)'\s*([,)])"),
        lambda m: f"Text(tr('{m.group(1)}'){m.group(2)}"
        if VN.search(m.group(1))
        else m.group(0),
    ),
    (
        re.compile(r"(?<![\w])Text\(\s*'((?:\\.|[^'\\])*)'\s*([,)])"),
        lambda m: f"Text(tr('{m.group(1)}'){m.group(2)}"
        if VN.search(m.group(1)) and not m.group(0).startswith("Text(tr(")
        else m.group(0),
    ),
    (
        re.compile(r"\bconst\s+Text\(\s*\"((?:\\.|[^\"\\])*)\"\s*([,)])"),
        lambda m: f'Text(tr("{m.group(1)}"){m.group(2)}'
        if VN.search(m.group(1))
        else m.group(0),
    ),
    (
        re.compile(r'(?<![\w])Text\(\s*"((?:\\.|[^"\\])*)"\s*([,)])'),
        lambda m: f'Text(tr("{m.group(1)}"){m.group(2)}'
        if VN.search(m.group(1))
        else m.group(0),
    ),
]

NAMED = [
    "hintText",
    "labelText",
    "helperText",
    "tooltip",
    "semanticLabel",
    "counterText",
    "prefixText",
    "suffixText",
    "restoreId",  # skip? no VN usually
    "message",
    "title",  # only when string not widget — careful
    "label",
    "subtitle",
    "headerValue",
    "obscuringCharacter",
]

# Only wrap named params when value is a plain string (not a widget).
# Do NOT wrap label/subtitle/title — often stored as VN source keys (NavItem, etc.).
for name in [
    "hintText",
    "labelText",
    "helperText",
    "tooltip",
    "semanticLabel",
    "counterText",
    "prefixText",
    "suffixText",
    "message",
]:
    PATTERNS.append(
        (
            re.compile(rf"\b{name}:\s*'((?:\\.|[^'\\])*)'"),
            lambda m, _n=name: f"{_n}: tr('{m.group(1)}')"
            if VN.search(m.group(1))
            else m.group(0),
        )
    )
    PATTERNS.append(
        (
            re.compile(rf'\b{name}:\s*"((?:\\.|[^"\\])*)"'),
            lambda m, _n=name: f'{_n}: tr("{m.group(1)}")'
            if VN.search(m.group(1))
            else m.group(0),
        )
    )

IMPORT_LINE = "import '../l10n/app_tr.dart';"
IMPORT_LINE_PKG = "import 'package:zkteco_flutter_client/l10n/app_tr.dart';"


def relative_import(dart_path: Path) -> str:
    # Prefer package import for reliability
    return "import 'package:zkteco_flutter_client/l10n/app_tr.dart';\n"


def should_skip(path: Path) -> bool:
    parts = set(path.parts)
    if "l10n" in parts:
        return True
    name = path.name
    if name.endswith(".g.dart") or name.endswith(".freezed.dart"):
        return True
    return False


def already_has_import(text: str) -> bool:
    return "l10n/app_tr.dart" in text


def process_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    text = original
    changed = False
    for cre, repl in PATTERNS:
        def _sub(m, _repl=repl):
            nonlocal changed
            out = _repl(m)
            if out != m.group(0):
                changed = True
            return out

        text = cre.sub(_sub, text)

    # Remove broken const before Text(tr(...))
    new_text, n = re.subn(r"\bconst\s+Text\(tr\(", "Text(tr(", text)
    if n:
        text = new_text
        changed = True

    if not changed:
        return False

    if not already_has_import(text):
        # Insert after last import
        lines = text.splitlines(keepends=True)
        insert_at = 0
        for i, line in enumerate(lines):
            if line.startswith("import "):
                insert_at = i + 1
        lines.insert(insert_at, relative_import(path))
        text = "".join(lines)

    path.write_text(text, encoding="utf-8")
    return True


def main() -> None:
    count = 0
    for p in sorted(ROOT.rglob("*.dart")):
        if should_skip(p):
            continue
        try:
            if process_file(p):
                count += 1
                print(p.relative_to(ROOT))
        except Exception as e:
            print(f"FAIL {p}: {e}")
    print(f"updated_files={count}")


if __name__ == "__main__":
    main()
