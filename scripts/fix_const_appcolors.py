#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(r"E:/SBOX CURSOR/ZKTecoADMS-master/flutter_client/lib")
n = 0
for path in ROOT.rglob("*.dart"):
    text = path.read_text(encoding="utf-8")
    # const AppColors.foo -> AppColors.foo (static const field, not constructor)
    new = re.sub(r"\bconst\s+(AppColors\.\w+)\b", r"\1", text)
    if new != text:
        path.write_text(new, encoding="utf-8")
        n += 1
        print(path.relative_to(ROOT))
print(f"fixed {n}")
