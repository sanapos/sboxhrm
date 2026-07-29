#!/usr/bin/env python3
"""Resume VI→EN map using MyMemory (more reliable than Google free)."""
from __future__ import annotations

import json
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from deep_translator import MyMemoryTranslator

ROOT = Path(__file__).resolve().parent
VN_SRC = ROOT / "vn_strings.json"
PARTIAL = ROOT / "en_ui_map.partial.json"
OUT = ROOT / "en_ui_map.json"
LOCK = threading.Lock()
WORKERS = 4

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
}


def translate_one(text: str) -> tuple[str, str]:
    # MyMemory max ~500 chars
    chunk = text[:480]
    for attempt in range(3):
        try:
            en = MyMemoryTranslator(source="vi-VN", target="en-GB").translate(chunk)
            if en and en.strip():
                return text, en.strip()
        except Exception:
            time.sleep(0.8 * (attempt + 1))
    return text, text


def main() -> None:
    items = json.loads(VN_SRC.read_text(encoding="utf-8"))
    vn_set = {i["vi"] for i in items if isinstance(i, dict) and i.get("vi")}
    done: dict[str, str] = {}
    if PARTIAL.exists():
        done.update(json.loads(PARTIAL.read_text(encoding="utf-8")))
    if OUT.exists():
        done.update(json.loads(OUT.read_text(encoding="utf-8")))
    done.update(OVERRIDES)

    todo = [s for s in sorted(vn_set, key=len) if s not in done]
    print(f"have={len(done)} todo={len(todo)}", flush=True)
    done_count = 0

    def flush() -> None:
        with LOCK:
            PARTIAL.write_text(json.dumps(done, ensure_ascii=False), encoding="utf-8")

    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(translate_one, s): s for s in todo}
        for fut in as_completed(futs):
            vi, en = fut.result()
            with LOCK:
                done[vi] = en
                done_count += 1
                if done_count % 25 == 0:
                    print(f"progress {done_count}/{len(todo)} map={len(done)}", flush=True)
                    flush()
            time.sleep(0.05)

    done.update(OVERRIDES)
    flush()
    OUT.write_text(json.dumps(done, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"done entries={len(done)}", flush=True)


if __name__ == "__main__":
    main()
