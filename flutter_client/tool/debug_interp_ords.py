#!/usr/bin/env python3
from pathlib import Path

t = Path(__file__).resolve().parents[1].joinpath(
    "lib", "widgets", "shift_swap_ui.dart"
).read_text(encoding="utf-8")
for line in t.splitlines():
    if "formatSwapDate(swap['createdAt'])" in line:
        i = line.index(")}'") + 2
        chunk = line[i : i + 8]
        print("chunk repr", repr(chunk))
        print("ords", [ord(c) for c in chunk])
