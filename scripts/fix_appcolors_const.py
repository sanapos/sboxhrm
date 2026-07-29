#!/usr/bin/env python3
"""Fix broken const Color / AppColors patterns after token migration."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(r"E:/SBOX CURSOR/ZKTecoADMS-master/flutter_client/lib")


def main() -> None:
    n = 0
    for path in ROOT.rglob("*.dart"):
        text = path.read_text(encoding="utf-8")
        orig = text
        # const AppColors.x.withValues(...)  -> AppColors.x.withValues(...)
        text = re.sub(
            r"const\s+(AppColors\.\w+)\.withValues",
            r"\1.withValues",
            text,
        )
        # Color(AppColors.primary) -> AppColors.primary
        text = re.sub(r"\bColor\((AppColors\.\w+)\)", r"\1", text)
        # const Color(AppColors.primary) already covered
        if text != orig:
            path.write_text(text, encoding="utf-8")
            n += 1
            print(path.relative_to(ROOT))
    print(f"fixed {n} files")


if __name__ == "__main__":
    main()
