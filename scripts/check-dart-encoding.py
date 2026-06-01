#!/usr/bin/env python3
"""Fail CI if Dart sources still contain Vietnamese encoding damage."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib"

BANNED_SUBSTRINGS = (
    "\ufffd",
    "Thi?t",
    "B?o hi?m",
    "Gi? v",
    "Gi? ra",
    "Gi? ",
    "Ca l?m",
    "C?u h",
    "ph?t",
    "Ph?t",
    "Thu? ",
    "Thu?",
    "Qu?n ",
    "Gi?m ",
    "bi?u ",
    "Ðang",
    "Ðã ",
    "Ði tr",
    "ch?m ",
    "ch?n ",
    "ngu?i",
    "d?ng BHXH",
    "T? l? ",
    "m?c ph",
    "Th? 2",
    "Thi?t b",
    "B? l?c",
    "cóó",
)

MOJIBAKE_IN_STR = re.compile(
    r"(?<=[A-Za-zÀ-ỹ])\?(?=[A-Za-zÀ-ỹ])|[\u00d0][a-zà-ỹ]"
)

STRING_LIT = re.compile(
    r"(?:r'(?:\\.|[^'\\])*'|r\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\")",
    re.DOTALL,
)


def check_file(path: Path) -> list[str]:
    issues: list[str] = []
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        return [f"invalid UTF-8 at byte {e.start}: {e.reason}"]

    for sub in BANNED_SUBSTRINGS:
        if sub in text:
            issues.append(f"contains {sub!r} ({text.count(sub)}x)")

    for m in STRING_LIT.finditer(text):
        s = m.group(0)
        if MOJIBAKE_IN_STR.search(s):
            issues.append(f"mojibake in string: {s[:60]!r}...")
            if len(issues) > 12:
                break

    return issues


def main() -> int:
    failures: list[tuple[str, list[str]]] = []
    n = 0
    for path in sorted(ROOT.rglob("*.dart")):
        if ".bak" in path.name:
            continue
        n += 1
        issues = check_file(path)
        if issues:
            failures.append((str(path.relative_to(ROOT.parent.parent)).replace("\\", "/"), issues))

    if not failures:
        print(f"OK: {n} dart files — encoding check passed")
        return 0

    print(f"FAIL: {len(failures)} file(s)")
    for rel, issues in failures[:40]:
        print(f"\n{rel}:")
        for i in issues[:8]:
            print(f"  - {i.encode('ascii', 'backslashreplace').decode('ascii')}")
    if len(failures) > 40:
        print(f"\n... +{len(failures) - 40} more files")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
