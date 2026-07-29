#!/usr/bin/env python3
from pathlib import Path
import re

p = Path(__file__).resolve().parents[1] / "lib" / "widgets" / "shift_swap_ui.dart"
t = p.read_text(encoding="utf-8")
for line in t.splitlines():
    if "Tạo lúc" in line or "tr('Tạo" in line:
        print(repr(line))
