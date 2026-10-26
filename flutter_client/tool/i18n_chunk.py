#!/usr/bin/env python3
"""Split the strings still lacking ko/ja/zh into translation chunks.

Workflow for new UI strings:
  1. python tool/i18n_extract.py        → tool/i18n/source.json
  2. python tool/i18n_chunk.py [N]      → tool/i18n/work/chunk_NN.jsonl (only new strings)
  3. translate each chunk into tool/i18n/work/out_NN_*.json following
     tool/i18n/glossary.md, then: python tool/i18n_check_chunk.py NN
  4. python tool/i18n_build.py          → tool/i18n/*.json + assets/l10n/*.json
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

from i18n_extract import parse_map

ROOT = Path(__file__).resolve().parent.parent
I18N = ROOT / "tool" / "i18n"
WORK = I18N / "work"


def known(lang: str) -> set[str]:
    p = I18N / f"{lang}.json"
    if not p.exists():
        return set()
    pack = json.loads(p.read_text(encoding="utf-8"))
    return set(pack["m"]) | {t[0] for t in pack["t"]}


def main() -> None:
    size = int(sys.argv[1]) if len(sys.argv) > 1 else 800
    src = json.loads((I18N / "source.json").read_text(encoding="utf-8"))
    en = parse_map(ROOT / "lib" / "l10n" / "en_ui_map.g.dart")
    en_extra = known("en")
    done = known("ko") & known("ja") & known("zh")

    items = []
    for vi in src["texts"] + src["templates"]:
        # en_ui_map.g.dart has entries "translated" to themselves — still needed.
        has_en = (vi in en and en[vi] != vi) or vi in en_extra
        if vi in done and has_en:
            continue
        it = {"id": len(items), "vi": vi}
        if vi in en and en[vi] != vi:
            it["en"] = en[vi]
        if not has_en:
            it["need_en"] = True
        items.append(it)

    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    (WORK / "items.json").write_text(json.dumps(items, ensure_ascii=False), encoding="utf-8")
    for c in range(0, len(items), size):
        with open(WORK / f"chunk_{c // size:02d}.jsonl", "w", encoding="utf-8") as f:
            for it in items[c:c + size]:
                f.write(json.dumps(it, ensure_ascii=False) + "\n")
    print(f"new strings={len(items)} chunks={-(-len(items) // size)}")


if __name__ == "__main__":
    main()
