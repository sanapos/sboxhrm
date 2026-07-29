#!/usr/bin/env python3
"""Merge + finish VI→EN map for full English UI via tr()."""
from __future__ import annotations

import json
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from deep_translator import GoogleTranslator

ROOT = Path(__file__).resolve().parent
LIB = ROOT.parent / "lib"
VN_SRC = ROOT / "vn_strings.json"
PARTIAL = ROOT / "en_ui_map.partial.json"
FULL = ROOT / "en_ui_map.json"
OUT = ROOT / "en_ui_map.json"
CACHE = ROOT / "en_ui_map.partial.json"
L10N = LIB / "l10n" / "app_localizations.dart"
LOCK = threading.Lock()
WORKERS = 10

# High-quality overrides (fix bad auto/seed translations)
OVERRIDES = {
    "Cái": "pcs",
    "Hủy phiếu": "Cancel document",
    "Hoạt động": "Active",
    "Công việc": "Tasks",
    "In": "Print",
    "Ra": "Out",
    "Vào": "In",
    "Ca": "Shift",
    "Công": "Work day",
    "Phép": "Leave",
    "Nghỉ": "Off",
    "Lễ": "Holiday",
    "Vắng": "Absent",
    "Chữ": "Text",
    "Cặp": "Pair",
    "Lớn": "Large",
    "lẻ": "odd",
    "tối": "evening",
    "giờ": "hour",
    "năm": "year",
    "bốn": "four",
    "sáu": "six",
    "bảy": "seven",
    "mốt": "one",
    "tại": "at",
    "gói": "package",
    "Gấp": "Urgent",
    "cần": "need",
    "Kẻ": "Rule",
    "tỷ": "billion",
    "CHỜ": "PENDING",
    "Máy Requests": "My Requests",
}


def parse_l10n_pairs() -> dict[str, str]:
    """Extract vi→en from AppLocalizations maps."""
    text = L10N.read_text(encoding="utf-8")
    # Find 'vi': { ... }, 'en': { ... }
    vi_m = re.search(r"'vi'\s*:\s*\{", text)
    en_m = re.search(r"'en'\s*:\s*\{", text)
    if not vi_m or not en_m:
        return {}

    def parse_block(start: int) -> dict[str, str]:
        i = text.find("{", start)
        depth = 0
        end = i
        for j in range(i, len(text)):
            c = text[j]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    end = j
                    break
        block = text[i + 1 : end]
        out: dict[str, str] = {}
        for m in re.finditer(
            r"'((?:\\.|[^'\\])*)'\s*:\s*'((?:\\.|[^'\\])*)'", block
        ):
            k = m.group(1).encode().decode("unicode_escape")
            v = m.group(2).encode().decode("unicode_escape")
            out[k] = v
        return out

    vi_map = parse_block(vi_m.start())
    en_map = parse_block(en_m.start())
    pairs: dict[str, str] = {}
    for key, vi in vi_map.items():
        en = en_map.get(key)
        if en and vi and vi != en:
            pairs[vi] = en
    return pairs


def translate_one(text: str) -> tuple[str, str]:
    try:
        en = GoogleTranslator(source="vi", target="en").translate(text)
        return text, (en or text).strip()
    except Exception:
        time.sleep(0.6)
        try:
            en = GoogleTranslator(source="vi", target="en").translate(text)
            return text, (en or text).strip()
        except Exception:
            return text, text


def main() -> None:
    # Refresh VN extract first if present
    extract = ROOT / "extract_vn_strings.py"
    if extract.exists():
        import subprocess

        subprocess.check_call(["python", str(extract)], cwd=str(ROOT))

    items = json.loads(VN_SRC.read_text(encoding="utf-8"))
    vn_set = {i["vi"] for i in items if isinstance(i, dict) and i.get("vi")}

    done: dict[str, str] = {}
    for path in (PARTIAL, FULL):
        if path.exists():
            for k, v in json.loads(path.read_text(encoding="utf-8")).items():
                if isinstance(k, str) and isinstance(v, str) and k.strip():
                    done[k] = v

    done.update(parse_l10n_pairs())
    done.update(OVERRIDES)

    todo = [s for s in sorted(vn_set) if s not in done]
    print(f"have={len(done)} todo={len(todo)} total_vn={len(vn_set)}", flush=True)

    done_count = 0

    def flush() -> None:
        with LOCK:
            CACHE.write_text(
                json.dumps(done, ensure_ascii=False), encoding="utf-8"
            )

    if todo:
        with ThreadPoolExecutor(max_workers=WORKERS) as ex:
            futs = {ex.submit(translate_one, s): s for s in todo}
            for fut in as_completed(futs):
                vi, en = fut.result()
                with LOCK:
                    done[vi] = en
                    done_count += 1
                    if done_count % 40 == 0:
                        print(
                            f"progress {done_count}/{len(todo)} map={len(done)}",
                            flush=True,
                        )
                        flush()

    done.update(OVERRIDES)
    flush()
    OUT.write_text(
        json.dumps(done, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"wrote {OUT} entries={len(done)}", flush=True)


if __name__ == "__main__":
    main()
