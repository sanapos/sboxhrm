#!/usr/bin/env python3
"""Wrap VN prefixes inside Dart interpolated strings: Text('Xin chào ${x}')."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
VN = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)

# Text('static${expr...}') — static has no $/{/' 
PAT = re.compile(r"Text\(\s*'([^'$'{]*)\$\{")


def dart_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def repl(m: re.Match[str]) -> str:
    prefix = m.group(1)
    if not VN.search(prefix):
        return m.group(0)
    if "tr(" in prefix:
        return m.group(0)
    # Text('prefix${...}') → Text('${tr('prefix')}${...}')
    return f"Text('${{tr('{dart_escape(prefix)}')}}${{"


def main() -> None:
    files = 0
    total = 0
    for p in sorted(ROOT.rglob("*.dart")):
        if "l10n" in p.parts:
            continue
        text = p.read_text(encoding="utf-8")
        new, n = PAT.subn(repl, text)
        if not n:
            continue
        if "l10n/app_tr.dart" not in new:
            lines = new.splitlines(keepends=True)
            insert_at = 0
            for i, line in enumerate(lines):
                if line.startswith("import "):
                    insert_at = i + 1
            lines.insert(
                insert_at,
                "import 'package:zkteco_flutter_client/l10n/app_tr.dart';\n",
            )
            new = "".join(lines)
        new = re.sub(r"\bconst\s+Text\(\$\{tr\(", "Text(${tr(", new)
        p.write_text(new, encoding="utf-8")
        files += 1
        total += n
        print(f"{p.relative_to(ROOT)} n={n}")
    print(f"files={files} replacements={total}")


if __name__ == "__main__":
    main()
