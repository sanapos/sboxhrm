#!/usr/bin/env python3
"""Patch DataTable cells/headers to use AppText (UTF-8 safe)."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
FILES = [
    "screens/payroll_report_screen.dart",
    "screens/work_schedule_screen.dart",
    "screens/advance_requests_screen.dart",
    "screens/schedule_approval_screen.dart",
    "screens/production_output_screen.dart",
    "screens/hr_report_screen.dart",
    "screens/advanced_reports_screen.dart",
    "screens/account_management_screen.dart",
]


def patch(path: Path) -> None:
    c = path.read_text(encoding="utf-8")
    if "widgets/app_text.dart" not in c:
        c = c.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/material.dart';\nimport '../widgets/app_text.dart';",
            1,
        )
    c = c.replace("DataCell(Text(", "DataCell(AppText.table(")
    c = re.sub(
        r"const\s+DataColumn\(\s*label:\s*Text\(",
        "DataColumn(label: AppText.label(",
        c,
    )
    c = re.sub(
        r"DataColumn\(\s*label:\s*Text\(",
        "DataColumn(label: AppText.label(",
        c,
    )
    path.write_text(c, encoding="utf-8")
    print(f"patched {path.name}")


def main() -> None:
    for rel in FILES:
        patch(ROOT / rel)


if __name__ == "__main__":
    main()
