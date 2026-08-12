# -*- coding: utf-8 -*-
import os
import re
import subprocess
import time

adb = r"C:\Users\TH DECOR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
s = "2637CCJ03256"
outdir = r"e:\SBOX CURSOR\ZKTecoADMS-master\.tmp-esp-audit"
apk = r"e:\SBOX CURSOR\ZKTecoADMS-master\flutter_pos\build\app\outputs\flutter-apk\app-release.apk"
log_path = os.path.join(outdir, "c20-final-smoke.log")


def log(msg: str) -> None:
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(msg + "\n")


def sh(*a: str) -> str:
    r = subprocess.run([adb, "-s", s, *a], capture_output=True)
    return (r.stdout or b"").decode("utf-8", "replace")


def dump() -> str:
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    p = os.path.join(outdir, "c20-ui.xml")
    sh("pull", "/sdcard/ui.xml", p)
    return open(p, encoding="utf-8", errors="replace").read()


def shot(name: str) -> None:
    sh("shell", "screencap", "-p", "/sdcard/c20.png")
    sh("pull", "/sdcard/c20.png", os.path.join(outdir, name))


def tap(x: int, y: int) -> None:
    sh("shell", "input", "tap", str(x), str(y))
    time.sleep(0.7)


def descs(raw: str):
    return re.findall(r'content-desc="([^"]{2,80})"', raw)


def find_contains(raw: str, needle: str):
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        raw,
    ):
        if needle in m.group(1):
            a, b, c, d = map(int, m.groups()[1:])
            return m.group(1), (a + c) // 2, (b + d) // 2, a, b, c, d
    return None


def main() -> None:
    open(log_path, "w", encoding="utf-8").write("")
    log(sh("install", "-r", apk)[-120:])
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
    # Home
    if find_contains(raw, "trang chủ") or find_contains(raw, "Phòng bàn"):
        tap(42, 72)
    time.sleep(2)
    raw = dump()
    more = find_contains(raw, "Nhiều hơn")
    tap(*(more[1:3] if more else (1728, 960)))
    time.sleep(2)
    shot("c20-more-ok.png")
    raw = dump()
    log("MORE: " + " | ".join(descs(raw)[:30]))

    # Warehouse tile: first cell of 6-col grid inside section
    wh_sec = find_contains(raw, "Trung tâm Kho")
    if wh_sec:
        a, b, c, d = wh_sec[3:]
        # title ~36px; grid cell width = section/6
        cell_w = max(80, (c - a) // 6)
        tx = a + cell_w // 2
        ty = b + 40 + (d - b - 40) // 2
        log(f"WH tap {tx},{ty} sec={a},{b}-{c},{d}")
        tap(tx, ty)
    else:
        tap(180, 400)
    time.sleep(3)
    shot("c20-wh-ok.png")
    raw = dump()
    log("WH: " + " | ".join(descs(raw)[:40]))

    sh("shell", "input", "keyevent", "4")
    time.sleep(1.5)
    raw = dump()

    # Settings gear — tooltip Cài đặt
    st = find_contains(raw, "Cài đặt")
    if st:
        log(f"settings via {st[0]!r}")
        tap(st[1], st[2])
    else:
        # profile row buttons: settings then logout near right
        profile = find_contains(raw, "Owner")
        if profile:
            # gear ~ left of logout; logout near right edge of profile card
            a, b, c, d = profile[3:]
            tap(c - 120, (b + d) // 2)
            log(f"settings geometric in profile {c-120},{(b+d)//2}")
        else:
            tap(1680, 175)
    time.sleep(3)
    shot("c20-settings-ok.png")
    raw = dump()
    log("SETTINGS: " + " | ".join(descs(raw)[:50]))
    log("DONE")


if __name__ == "__main__":
    main()
