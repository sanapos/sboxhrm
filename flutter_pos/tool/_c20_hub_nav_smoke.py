# -*- coding: utf-8 -*-
import os
import re
import subprocess
import time

adb = r"C:\Users\TH DECOR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
s = "2637CCJ03256"
outdir = r"e:\SBOX CURSOR\ZKTecoADMS-master\.tmp-esp-audit"
log_path = os.path.join(outdir, "c20-nav-smoke.log")
apk = r"e:\SBOX CURSOR\ZKTecoADMS-master\flutter_pos\build\app\outputs\flutter-apk\app-release.apk"


def log(msg: str) -> None:
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(msg + "\n")


def sh(*a: str) -> str:
    r = subprocess.run([adb, "-s", s, *a], capture_output=True)
    return (r.stdout or b"").decode("utf-8", "replace") + (
        r.stderr or b""
    ).decode("utf-8", "replace")


def dump() -> str:
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    p = os.path.join(outdir, "c20-ui.xml")
    sh("pull", "/sdcard/ui.xml", p)
    return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""


def shot(name: str) -> None:
    sh("shell", "screencap", "-p", "/sdcard/c20.png")
    sh("pull", "/sdcard/c20.png", os.path.join(outdir, name))


def tap(x: int, y: int) -> None:
    sh("shell", "input", "tap", str(x), str(y))
    time.sleep(0.5)


def find_desc(raw: str, *needles: str):
    for needle in needles:
        for m in re.finditer(
            r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        ):
            if needle in m.group(1):
                a, b, c, d = map(int, m.groups()[1:])
                return m.group(1), (a + c) // 2, (b + d) // 2
    return None


def find_tooltip_button(raw: str, *needles: str):
    # IconButtons may expose tooltip as content-desc
    hit = find_desc(raw, *needles)
    if hit:
        return hit
    # Fallback: leftmost clickable in top bar with empty desc
    return None


def main() -> None:
    open(log_path, "w", encoding="utf-8").write("")
    log(sh("install", "-r", apk)[-200:])
    sh("shell", "am", "force-stop", "sbox.sana.vn.pos.flutter")
    sh(
        "shell",
        "am",
        "start",
        "-n",
        "sbox.sana.vn.pos.flutter/vn.sana.sbox.sbox_pos.MainActivity",
    )
    time.sleep(5)
    raw = dump()
    descs = re.findall(r'content-desc="([^"]{2,60})"', raw)
    log("START: " + " | ".join(descs[:25]))

    # Tap Home (tooltip Về trang chủ) or first IconButton near left
    home = find_desc(raw, "Về trang chủ", "trang chủ", "Home")
    if home:
        log(f"home via desc {home[0]}")
        tap(home[1], home[2])
    else:
        # First empty button in top row y~40-110, x small
        cand = None
        for m in re.finditer(
            r'clickable="true"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        ):
            a, b, c, d = map(int, m.groups())
            if b < 120 and d < 160 and a < 80 and (c - a) < 100:
                cand = ((a + c) // 2, (b + d) // 2)
                break
        if not cand:
            # try explicit left home zone
            cand = (40, 70)
        log(f"home tap fallback {cand}")
        tap(*cand)
    time.sleep(2)
    shot("c20-after-home.png")
    raw = dump()
    descs = re.findall(r'content-desc="([^"]{2,60})"', raw)
    log("AFTER_HOME: " + " | ".join(descs[:40]))

    # Bottom tabs: Tổng quan / Hàng hóa / Bán hàng / Hóa đơn / Nhiều hơn
    more = find_desc(raw, "Nhiều hơn", "More")
    if more:
        tap(more[1], more[2])
        log(f"tab more {more[0]}")
    else:
        # 5th slot of bottom nav ~ y>900
        for m in re.finditer(
            r'clickable="true"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        ):
            a, b, c, d = map(int, m.groups())
            if b > 880:
                log(f"bottom clickable {a},{b}-{c},{d}")
        # try rightmost bottom fifth
        tap(1728, 960)
        log("tab more geometric")
    time.sleep(2)
    shot("c20-more.png")
    raw = dump()
    descs = re.findall(r'content-desc="([^"]{2,60})"', raw)
    log("MORE: " + " | ".join(descs[:50]))

    for label in ("Trung tâm Kho", "Thiết lập POS", "Thiết lập"):
        hit = find_desc(raw, label)
        if hit:
            tap(hit[1], hit[2])
            log(f"open {hit[0]}")
            time.sleep(3)
            shot(
                "c20-wh.png"
                if "Kho" in label
                else "c20-settings.png"
            )
            raw2 = dump()
            log(f"{label}: " + " | ".join(re.findall(r'content-desc="([^"]{2,60})"', raw2)[:40]))
            sh("shell", "input", "keyevent", "4")
            time.sleep(1.5)
            raw = dump()

    log("DONE")


if __name__ == "__main__":
    main()
