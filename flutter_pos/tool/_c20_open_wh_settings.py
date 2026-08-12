# -*- coding: utf-8 -*-
import os
import re
import subprocess
import time

adb = r"C:\Users\TH DECOR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
s = "2637CCJ03256"
outdir = r"e:\SBOX CURSOR\ZKTecoADMS-master\.tmp-esp-audit"
log_path = os.path.join(outdir, "c20-wh-settings.log")


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
    sh("shell", "am", "force-stop", "sbox.sana.vn.pos.flutter")
    time.sleep(0.5)
    sh(
        "shell",
        "am",
        "start",
        "-n",
        "sbox.sana.vn.pos.flutter/vn.sana.sbox.sbox_pos.MainActivity",
    )
    time.sleep(5)
    raw = dump()
    log("START: " + " | ".join(descs(raw)[:20]))

    # Home
    home = find_contains(raw, "trang chủ") or find_contains(raw, "Về trang chủ")
    if home:
        tap(home[1], home[2])
    else:
        tap(42, 72)
    time.sleep(2)
    raw = dump()
    log("HOME: " + " | ".join(descs(raw)[:25]))

    more = find_contains(raw, "Nhiều hơn")
    if more:
        tap(more[1], more[2])
    else:
        tap(1728, 960)
    time.sleep(2)
    shot("c20-more-final.png")
    raw = dump()
    log("MORE: " + " | ".join(descs(raw)[:40]))
    # dump all clickables with desc for debug
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        raw,
    ):
        if m.group(1) and int(m.group(3)) < 700:
            log(
                f"NODE {m.group(2)},{m.group(3)}-{m.group(4)},{m.group(5)} | {m.group(1).replace(chr(10),' / ')}"
            )

    wh = find_contains(raw, "Trung tâm Kho") or find_contains(raw, "Kho hàng")
    if wh:
        log(f"tap WH {wh[0]!r} center={wh[1]},{wh[2]} bounds={wh[3:]}")
        tap(wh[1], wh[2])
    else:
        log("WH not found, geometric")
        tap(300, 340)
    time.sleep(3)
    shot("c20-wh-final.png")
    raw = dump()
    log("WH: " + " | ".join(descs(raw)[:40]))

    # back to more
    sh("shell", "input", "keyevent", "4")
    time.sleep(1.5)
    raw = dump()
    # settings gear — profile card often has settings icon button without text
    # Prefer content-desc Thiết lập if any
    st = find_contains(raw, "Thiết lập POS") or find_contains(raw, "Thiết lập")
    if st:
        log(f"tap settings label {st[0]!r}")
        tap(st[1], st[2])
    else:
        # scroll down for settings section
        sh("shell", "input", "swipe", "960", "800", "960", "300", "300")
        time.sleep(1)
        raw = dump()
        st = find_contains(raw, "Thiết lập POS") or find_contains(raw, "Thiết lập")
        if st:
            log(f"tap settings after scroll {st[0]!r}")
            tap(st[1], st[2])
        else:
            # gear icon: buttons on profile row, right side
            btns = [
                tuple(map(int, m.groups()))
                for m in re.finditer(
                    r'class="android.widget.Button"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
                    raw,
                )
            ]
            log(f"buttons={btns[:20]}")
            gear = [b for b in btns if 100 < b[1] < 280 and b[0] > 1400]
            if gear:
                g = gear[0]
                tap((g[0] + g[2]) // 2, (g[1] + g[3]) // 2)
                log(f"tap gear {g}")
            else:
                # from screenshot gear left of logout on profile
                tap(1680, 175)
                log("tap gear geometric")
    time.sleep(3)
    shot("c20-settings-final.png")
    raw = dump()
    log("SETTINGS: " + " | ".join(descs(raw)[:50]))
    log("DONE")


if __name__ == "__main__":
    main()
