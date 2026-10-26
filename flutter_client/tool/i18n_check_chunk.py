#!/usr/bin/env python3
"""Validate translated chunk output: python tool/i18n_check_chunk.py <chunk-number>

Reads tool/i18n/work/chunk_NN.jsonl and every tool/i18n/work/out_NN_*.json part
({"<id>": {"ko": ..., "ja": ..., "zh": ..., "en": ...}}), prints problems, and
writes the merged result to tool/i18n/work/done_NN.json when nothing is wrong.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

WORK = Path(__file__).resolve().parent / "i18n" / "work"
LANGS = ("ko", "ja", "zh")
VN = re.compile(
    r"[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ"
    r"ÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]")
DONG = re.compile(r"(?<![^\W\d_])[đĐ](?![^\W\d_])|VNĐ|₫")
HOLE = re.compile(r"\{\d+\}")


def edge_ws(s: str) -> tuple[str, str]:
    return s[: len(s) - len(s.lstrip())], s[len(s.rstrip()):]


def main() -> None:
    n = int(sys.argv[1])
    items = [json.loads(l) for l in (WORK / f"chunk_{n:02d}.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    merged: dict[str, dict] = {}
    for p in sorted(WORK.glob(f"out_{n:02d}_*.json")):
        try:
            merged.update(json.loads(p.read_text(encoding="utf-8")))
        except json.JSONDecodeError as e:
            print(f"INVALID JSON {p.name}: {e}")
            return
    problems = 0
    for it in items:
        key = str(it["id"])
        tr = merged.get(key)
        if not isinstance(tr, dict):
            print(f"MISSING id {key}")
            problems += 1
            continue
        langs = LANGS + (("en",) if it.get("need_en") else ())
        holes = sorted(HOLE.findall(it["vi"]))
        lead, trail = edge_ws(it["vi"])
        for lang in langs:
            v = tr.get(lang)
            if not isinstance(v, str) or (not v.strip() and it["vi"].strip()):
                print(f"EMPTY id {key} [{lang}]")
                problems += 1
                continue
            if sorted(HOLE.findall(v)) != holes:
                print(f"PLACEHOLDERS id {key} [{lang}]: {v!r} vs {it['vi']!r}")
                problems += 1
            if (VN.search(DONG.sub("", v)) and not tr.get("keep_vn")
                    and not VN.search(DONG.sub("", it.get("en", "x")))):
                print(f"VIETNAMESE LEFT id {key} [{lang}]: {v!r}")
                problems += 1
            if edge_ws(v) != (lead, trail):
                print(f"WHITESPACE id {key} [{lang}]: {v!r} vs {it['vi']!r}")
                problems += 1
    print(f"chunk {n:02d}: items={len(items)} translated={len(merged)} problems={problems}")
    if problems == 0:
        (WORK / f"done_{n:02d}.json").write_text(
            json.dumps(merged, ensure_ascii=False), encoding="utf-8")
        print("OK -> done file written")


if __name__ == "__main__":
    main()
