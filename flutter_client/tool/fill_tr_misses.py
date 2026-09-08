"""Dump tr() VN misses and translate into en_ui_map.json, then regenerate Dart."""
from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB = HERE.parent / "lib"
DART = LIB / "l10n" / "en_ui_map.g.dart"
JSON_MAP = HERE / "en_ui_map.json"

VN = re.compile(
    r"[ăâđêôơưĂÂĐÊÔƠƯáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ"
    r"ÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ]"
)
TR = re.compile(r"\btr(?:N|Or)?\(\s*'((?:[^'\\\n]|\\.)*)'")
KEY_RE = re.compile(
    r"^\s*r?'((?:[^'\\]|\\.)*)':\s*r?'((?:[^'\\]|\\.)*)',\s*$", re.M
)


def unescape(s: str) -> str:
    return (
        s.replace(r"\\", "\x00")
        .replace(r"\'", "'")
        .replace(r"\n", "\n")
        .replace("\x00", "\\")
    )


def collect_misses() -> list[str]:
    src = DART.read_text(encoding="utf-8")
    keys = set()
    for k, _v in KEY_RE.findall(src):
        keys.add(unescape(k))
    misses: dict[str, str] = {}
    for p in LIB.rglob("*.dart"):
        if p.name.endswith(".g.dart"):
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        for m in TR.finditer(text):
            raw = m.group(1)
            s = unescape(raw)
            if not VN.search(s):
                continue
            if s in keys:
                continue
            misses.setdefault(s, str(p.relative_to(LIB)))
    return sorted(misses)


def translate(items: list[str]) -> dict[str, str]:
    from deep_translator import GoogleTranslator

    tx = GoogleTranslator(source="vi", target="en")
    done: dict[str, str] = {}
    batch: list[str] = []
    blen = 0

    def flush() -> None:
        nonlocal batch, blen
        if not batch:
            return
        joined = "\n".join(batch)
        for attempt in range(4):
            try:
                out = tx.translate(joined)
                lines = out.split("\n")
                if len(lines) != len(batch):
                    # fallback one-by-one
                    for s in batch:
                        done[s] = tx.translate(s)
                        time.sleep(0.05)
                else:
                    for s, en in zip(batch, lines):
                        done[s] = en.strip() or s
                break
            except Exception:
                time.sleep(0.8 * (attempt + 1))
        else:
            for s in batch:
                done.setdefault(s, s)
        print(f"  translated {len(done)}/{len(items)}", flush=True)
        batch, blen = [], 0
        time.sleep(0.25)

    for s in items:
        # Skip huge blobs / interpolated templates — fragment engine handles them.
        if "$" in s or len(s) > 180:
            continue
        batch.append(s)
        blen += len(s) + 1
        if blen > 2800 or len(batch) >= 25:
            flush()
    flush()
    return done


def main() -> None:
    misses = collect_misses()
    (HERE / "tr_misses.json").write_text(
        json.dumps(misses, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    print(f"misses={len(misses)}")
    data = json.loads(JSON_MAP.read_text(encoding="utf-8"))
    todo = [s for s in misses if s not in data]
    print(f"to_translate={len(todo)}")
    if todo:
        added = translate(todo)
        data.update(added)
        JSON_MAP.write_text(
            json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8"
        )
        print(f"map_size={len(data)}")
    os.system(f'python "{HERE / "generate_en_ui_map_dart.py"}"')


if __name__ == "__main__":
    main()
