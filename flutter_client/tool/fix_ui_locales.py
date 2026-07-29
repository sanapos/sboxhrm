#!/usr/bin/env python3
"""Replace hardcoded Locale('vi') in UI date pickers with appUiLocale()."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
SKIP_PARTS = {"l10n", "pos_print", "pos_thermal", "pos_kitchen_print", "pos_sale_order_print",
              "pos_barcode_print", "pos_stock", "pos_end_of_day_print", "pos_label",
              "pos_purchase_receipt_print", "pos_print_template"}

IMPORT = "import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';\n"


def should_skip(path: Path) -> bool:
    s = str(path).replace("\\", "/")
    if "/l10n/" in s:
        return True
    name = path.name
    for part in SKIP_PARTS:
        if part in name:
            return True
    return False


def process(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    original = text
    text2 = re.sub(
        r"locale:\s*const\s+Locale\(\s*'vi'\s*(?:,\s*'VN'\s*)?\)",
        "locale: appUiLocale()",
        text,
    )
    text2 = re.sub(
        r"locale:\s*Locale\(\s*'vi'\s*(?:,\s*'VN'\s*)?\)",
        "locale: appUiLocale()",
        text2,
    )
    if text2 == original:
        return False
    if "app_ui_locale.dart" not in text2:
        lines = text2.splitlines(keepends=True)
        insert_at = 0
        for i, line in enumerate(lines):
            if line.startswith("import "):
                insert_at = i + 1
        lines.insert(insert_at, IMPORT)
        text2 = "".join(lines)
    path.write_text(text2, encoding="utf-8")
    return True


def main() -> None:
    n = 0
    for p in ROOT.rglob("*.dart"):
        if should_skip(p):
            continue
        if process(p):
            n += 1
            print(p.relative_to(ROOT))
    print(f"updated_files={n}")


if __name__ == "__main__":
    main()
