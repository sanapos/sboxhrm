#!/usr/bin/env python3
"""Generate lib/l10n/en_ui_map.g.dart from en_ui_map.json."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "en_ui_map.json"
# Prefer partial if full not ready
PARTIAL = ROOT / "en_ui_map.partial.json"
OUT = ROOT.parent / "lib" / "l10n" / "en_ui_map.g.dart"


def dart_escape(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("\n", "\\n")
        .replace("\r", "")
        .replace("$", "\\$")
    )


def main() -> None:
    path = SRC if SRC.exists() else PARTIAL
    if not path.exists():
        raise SystemExit(f"missing {SRC} or {PARTIAL}")
    data = json.loads(path.read_text(encoding="utf-8"))
    lines = [
        "// GENERATED — do not edit by hand. Run: python tool/generate_en_ui_map_dart.py",
        "// ignore_for_file: prefer_single_quotes",
        "",
        "/// Vietnamese UI string → English. Used by [tr] when locale is English.",
        "const Map<String, String> kEnUiMap = <String, String>{",
    ]
    for vi, en in sorted(data.items(), key=lambda x: x[0]):
        if not isinstance(vi, str) or not isinstance(en, str):
            continue
        if not vi.strip():
            continue
        lines.append(f"  '{dart_escape(vi)}': '{dart_escape(en)}',")
    lines.append("};")
    lines.append("")
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUT} entries={len(data)}")


if __name__ == "__main__":
    main()
