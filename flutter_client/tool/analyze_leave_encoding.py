#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
raw = p.read_bytes()
for enc in ["utf-8", "cp1258", "latin1", "cp1252"]:
    try:
        t = raw.decode(enc)
        bad = sum(1 for c in t if c == "\ufffd")
        print(enc, "replacement", bad, "T? ng" in t, "Đến" in t)
    except Exception as e:
        print(enc, "FAIL", e)

t = raw.decode("utf-8", errors="replace")
for i, line in enumerate(t.splitlines(), 1):
    if "'" in line and "?" in line:
        if any(
            x in line
            for x in ["ng", "duy", "ch", "nh", "T?", "mu?", "H?y", "X?a"]
        ):
            if "int?" not in line and "String?" not in line and "bool?" not in line:
                print(f"{i}: {line.strip()[:120]}")
