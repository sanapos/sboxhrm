#!/usr/bin/env python3
"""Scan Dart lib for remaining Vietnamese encoding damage in strings/comments."""
from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "flutter_client" / "lib"

# Mid-word ? often means lost diacritic (not Dart ?. or ?? widget)
MOJIBAKE = re.compile(
    r"(?<=[A-Za-zÀ-ỹ])\?(?=[A-Za-zÀ-ỹ])|"
    r"\ufffd|"
    r"Ð[a-z]|"  # wrong capital D stroke
    r"[\u0080-\u009f]"
)

STRING_LIT = re.compile(r"'([^'\\]*(?:\\.[^'\\]*)*)'|\"([^\"\\]*(?:\\.[^\"\\]*)*)\"")

PRIORITY = [
    ("Trang chủ / Landing", ("dashboard_screen", "landing_screen", "main_layout")),
    ("Phạt", ("penalty_", "bonus_penalty")),
    ("Bảo hiểm", ("insurance_")),
    ("Thuế", ("tax_")),
    ("Lương / Thu chi", ("salary_", "cash_", "advance_", "payroll")),
    ("Chấm công", ("attendance", "shift_", "mobile_attendance", "work_schedule")),
    ("Thiết bị / NV", ("device_users", "employees_screen", "branch_")),
    ("HRM khác", ("holiday_", "allowance_", "kpi_", "meal_")),
]


def categorize(path: str) -> str:
    for label, keys in PRIORITY:
        if any(k in path for k in keys):
            return label
    return "Khác"


def main() -> None:
    by_file: dict[str, list[str]] = {}
    invalid: list[str] = []

    for p in sorted(ROOT.rglob("*.dart")):
        if ".bak" in p.name:
            continue
        rel = str(p.relative_to(ROOT.parent)).replace("\\", "/")
        try:
            text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            invalid.append(rel)
            continue

        samples: list[str] = []
        for m in STRING_LIT.finditer(text):
            s = m.group(1) or m.group(2) or ""
            if len(s) < 4 or not MOJIBAKE.search(s):
                continue
            if s.count("?") == 1 and "?" in s and "http" in s.lower():
                continue
            samples.append(s[:80])

        # Comments with mojibake (UI often hardcoded in comments nearby - less critical)
        for i, line in enumerate(text.splitlines(), 1):
            if "//" in line and MOJIBAKE.search(line) and len(samples) < 20:
                stripped = line.strip()[:90]
                if stripped not in samples and MOJIBAKE.search(stripped):
                    samples.append(f"L{i}: {stripped}")

        if samples:
            by_file[rel] = samples[:15]

    by_cat: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for rel, samples in by_file.items():
        by_cat[categorize(rel)].append((rel, len(samples)))

    print(f"INVALID_UTF8_FILES={len(invalid)}")
    for f in invalid:
        print(f"  {f}")
    print(f"FILES_WITH_MOJIBAKE={len(by_file)}")
    print(f"TOTAL_SAMPLE_HITS={sum(len(v) for v in by_file.values())}")

    for label, _ in PRIORITY + [("Khác", ())]:
        items = sorted(by_cat.get(label, []), key=lambda x: -x[1])
        if not items:
            continue
        print(f"\n## {label} — {len(items)} file(s)")
        for rel, n in items[:12]:
            print(f"  {rel} ({n} samples)")
            for s in by_file[rel][:2]:
                esc = s.encode("unicode_escape").decode("ascii")[:100]
                print(f"    · {esc}")
        if len(items) > 12:
            print(f"  ... +{len(items) - 12} files")

    # Top 20 worst files
    print("\n## Top 20 files (most samples)")
    worst = sorted(by_file.items(), key=lambda x: -len(x[1]))[:20]
    for rel, samples in worst:
        print(f"  {len(samples):3d}  {rel}")


if __name__ == "__main__":
    main()
