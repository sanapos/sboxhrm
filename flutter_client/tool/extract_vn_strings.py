#!/usr/bin/env python3
"""Extract unique Vietnamese string literals from Flutter lib/."""
from __future__ import annotations

import collections
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
OUT = Path(__file__).resolve().parent / "vn_strings.json"

VN = re.compile(
    r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
    r"ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ]"
)

# Single/double quoted strings (no raw/triple for simplicity)
STR = re.compile(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"")


def unescape(s: str) -> str:
    body = s[1:-1]
    return (
        body.replace(r"\n", "\n")
        .replace(r"\t", "\t")
        .replace(r"\'", "'")
        .replace(r"\"", '"')
        .replace(r"\\", "\\")
    )


def main() -> None:
    counts: collections.Counter[str] = collections.Counter()
    files = 0
    for p in ROOT.rglob("*.dart"):
        if "l10n" in p.parts:
            continue
        files += 1
        text = p.read_text(encoding="utf-8", errors="ignore")
        for m in STR.finditer(text):
            body = unescape(m.group(0)).strip()
            if len(body) < 2 or len(body) > 180:
                continue
            if "$" in body or "{" in body:  # skip interpolations
                continue
            if not VN.search(body):
                continue
            # skip import/package-ish
            if body.startswith("package:") or "/" in body and body.endswith(".dart"):
                continue
            counts[body] += 1

    items = [{"vi": s, "count": c} for s, c in counts.most_common()]
    OUT.write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"files={files} unique={len(counts)} occurrences={sum(counts.values())}")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
