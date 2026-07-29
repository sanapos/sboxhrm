#!/usr/bin/env python3
"""Generate out_008..011.json from todo files and translation lists."""
import json
from pathlib import Path

DIR = Path(__file__).parent

# Import translation lists
from trans_008 import T as T8
from trans_009 import T as T9
from trans_010 import T as T10
from trans_011 import T as T11

CHUNKS = [
    (8, T8),
    (9, T9),
    (10, T10),
    (11, T11),
]


def main():
    for num, translations in CHUNKS:
        todo_path = DIR / f"todo_{num:03d}.json"
        out_path = DIR / f"out_{num:03d}.json"
        with open(todo_path, encoding="utf-8") as f:
            keys = json.load(f)
        if len(keys) != len(translations):
            raise SystemExit(
                f"todo_{num:03d}.json has {len(keys)} keys but trans_{num:03d} has {len(translations)} translations"
            )
        result = {k: v for k, v in zip(keys, translations)}
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"out_{num:03d}.json: {len(result)} entries")


if __name__ == "__main__":
    main()
