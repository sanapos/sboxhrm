#!/usr/bin/env python3
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "repair",
    Path(__file__).parent / "repair-dart-encoding.py",
)
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)

path = Path(__file__).parents[1] / "flutter_client" / "lib" / "app" / "app.dart"
orig = path.read_text(encoding="utf-8")
fixed = repair.repair_text(orig)
for i, (a, b) in enumerate(zip(orig.splitlines(), fixed.splitlines())):
    if a != b and ("args" in a or "args" in b or "iPhone" in a):
        print(f"line {i+1}: {a!r} -> {b!r}")
if "argsố" in fixed or "args?" not in fixed.split("args?")[1:2]:
    print("args check:", "argsố" in fixed, "args?" in fixed)
print("OK" if "args?['email']" in fixed and "argsố" not in fixed else "FAIL")
