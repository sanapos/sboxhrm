#!/usr/bin/env python3
"""Turn tr(<String? expr>) into trN(...) at analyzer-reported positions."""
from __future__ import annotations

import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NEEDLE = "The argument type 'String?' can't be assigned to the parameter type 'String'"


def analyzer_hits() -> dict[Path, list[tuple[int, int]]]:
    out = subprocess.run(
        ["dart", "analyze", "lib", "--format=machine"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        shell=True,
    )
    hits: dict[Path, list[tuple[int, int]]] = defaultdict(list)
    for line in (out.stdout + out.stderr).splitlines():
        parts = line.split("|")
        if len(parts) < 8 or parts[0] != "ERROR":
            continue
        if NEEDLE not in parts[7]:
            continue
        hits[Path(parts[3])].append((int(parts[4]), int(parts[5])))
    return hits


def main() -> None:
    hits = analyzer_hits()
    if not hits:
        print("no nullable tr() sites")
        return
    total = 0
    for path, positions in hits.items():
        lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
        for line_no, col in sorted(positions, reverse=True):
            line = lines[line_no - 1]
            # Find the tr( that opens just before the offending argument.
            head = line[: col - 1]
            m = None
            for m in re.finditer(r"(?<![\w.$])tr\(", head):
                pass
            if m is None:
                print(f"skip {path.name}:{line_no}:{col}")
                continue
            lines[line_no - 1] = head[: m.start()] + "trN(" + head[m.end():] + line[col - 1:]
            total += 1
        path.write_text("".join(lines), encoding="utf-8")
        print(f"{path.name} fixed={len(positions)}")
    print(f"total={total}")


if __name__ == "__main__":
    sys.exit(main())
