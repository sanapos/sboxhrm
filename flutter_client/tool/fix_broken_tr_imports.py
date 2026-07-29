#!/usr/bin/env python3
"""Move misplaced app_tr import out of multi-line import (if/show)."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"
TR = "import 'package:zkteco_flutter_client/l10n/app_tr.dart';"


def main() -> None:
    n = 0
    for p in sorted(ROOT.rglob("*.dart")):
        lines = p.read_text(encoding="utf-8").splitlines(keepends=True)
        out = []
        i = 0
        changed = False
        while i < len(lines):
            line = lines[i]
            # Detect: import 'x' (no semicolon) then app_tr then if/show
            if (
                line.startswith("import ")
                and not line.rstrip().endswith(";")
                and i + 2 < len(lines)
                and "l10n/app_tr.dart" in lines[i + 1]
                and (
                    lines[i + 2].lstrip().startswith("if ")
                    or lines[i + 2].lstrip().startswith("show ")
                )
            ):
                out.append(line)
                out.append(lines[i + 2])
                # skip app_tr mid-line; add later
                i += 3
                changed = True
                continue
            out.append(line)
            i += 1
        if not changed:
            continue
        text = "".join(out)
        if TR not in text:
            # insert after last import
            lines2 = text.splitlines(keepends=True)
            insert_at = 0
            for j, ln in enumerate(lines2):
                if ln.startswith("import ") or (
                    j > 0
                    and (
                        lines2[j - 1].startswith("import ")
                        or lines2[j - 1].lstrip().startswith("if ")
                        or lines2[j - 1].lstrip().startswith("show ")
                    )
                    and (ln.lstrip().startswith("if ") or ln.lstrip().startswith("show ") or ln.startswith("import "))
                ):
                    insert_at = j + 1
            # simpler: after first blank line following imports
            insert_at = 0
            for j, ln in enumerate(lines2):
                if ln.startswith("import ") or ln.lstrip().startswith("if ") or ln.lstrip().startswith("show "):
                    insert_at = j + 1
            lines2.insert(insert_at, TR + "\n")
            text = "".join(lines2)
        p.write_text(text, encoding="utf-8")
        n += 1
        print(p.relative_to(ROOT))
    print(f"files={n}")


if __name__ == "__main__":
    main()
