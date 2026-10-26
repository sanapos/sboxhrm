#!/usr/bin/env python3
"""Merge translated chunks into the app's language packs (adds to the existing ones).

Inputs : tool/i18n/work/items.json + tool/i18n/work/done_NN.json (see i18n_check_chunk.py)
Outputs: tool/i18n/{ko,ja,zh,en}.json — reviewed translations kept in the repo
         assets/l10n/{ko,ja,zh,en}.json — packs loaded by lib/l10n/app_tr.dart
           {"m": {vietnamese: text}, "t": [[vietnameseTemplate, template], ...]}
English only carries what lib/l10n/en_ui_map.g.dart lacks (new strings + templates).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
I18N = ROOT / "tool" / "i18n"
WORK = I18N / "work"
ASSETS = ROOT / "assets" / "l10n"
HOLE = re.compile(r"\{\d+\}")


def main() -> None:
    items = json.loads((WORK / "items.json").read_text(encoding="utf-8"))
    done: dict[str, dict] = {}
    for p in sorted(WORK.glob("done_*.json")):
        done.update(json.loads(p.read_text(encoding="utf-8")))

    # Start from the packs already in the repo, so a run over new strings only adds.
    packs = {}
    for lang in ("ko", "ja", "zh", "en"):
        p = I18N / f"{lang}.json"
        packs[lang] = (json.loads(p.read_text(encoding="utf-8")) if p.exists()
                       else {"m": {}, "t": []})
    missing = 0
    for it in items:
        tr = done.get(str(it["id"]))
        if not tr:
            missing += 1
            continue
        vi = it["vi"]
        is_template = bool(HOLE.search(vi))
        for lang, pack in packs.items():
            if lang == "en" and not it.get("need_en"):
                continue
            text = tr.get(lang)
            if not text:
                continue
            if is_template:
                pack["t"] = [t for t in pack["t"] if t[0] != vi] + [[vi, text]]
            else:
                pack["m"][vi] = text

    ASSETS.mkdir(parents=True, exist_ok=True)
    for lang, pack in packs.items():
        pack["m"] = dict(sorted(pack["m"].items()))
        pack["t"].sort()
        (I18N / f"{lang}.json").write_text(
            json.dumps(pack, ensure_ascii=False, indent=1), encoding="utf-8")
        (ASSETS / f"{lang}.json").write_text(
            json.dumps(pack, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        print(f"{lang}: texts={len(pack['m'])} templates={len(pack['t'])}")
    print(f"items without translation: {missing}")


if __name__ == "__main__":
    main()
