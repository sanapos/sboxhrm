# -*- coding: utf-8 -*-
import os
import re
import subprocess
import time

adb = r"C:\Users\TH DECOR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
s = "2637CCJ03256"
outdir = r"e:\SBOX CURSOR\ZKTecoADMS-master\.tmp-esp-audit"
log_path = os.path.join(outdir, "c20-smoke.log")


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
    if not os.path.exists(p):
        return ""
    return open(p, encoding="utf-8", errors="replace").read()


def tap(x: int, y: int) -> None:
    sh("shell", "input", "tap", str(x), str(y))
    time.sleep(0.4)


def shot(name: str) -> None:
    sh("shell", "screencap", "-p", "/sdcard/c20.png")
    sh("pull", "/sdcard/c20.png", os.path.join(outdir, name))


def descs_of(raw: str) -> list[str]:
    return re.findall(r'content-desc="([^"]{2,80})"', raw)


def main() -> None:
    open(log_path, "w", encoding="utf-8").write("")
    sh("shell", "input", "keyevent", "3")
    time.sleep(0.4)
    sh(
        "shell",
        "am",
        "start",
        "-n",
        "sbox.sana.vn.pos.flutter/vn.sana.sbox.sbox_pos.MainActivity",
    )
    time.sleep(5)
    raw = dump()
    descs = descs_of(raw)
    log("START: " + " | ".join(descs[:30]))

    joined = " ".join(descs)
    need_login = any(
        k in joined
        for k in ("Chào mừng", "CỬA HÀNG", "Quên mật khẩu", "Đăng nhập", "EMAIL")
    )
    log(f"need_login={need_login}")

    if need_login:
        sh("shell", "input", "keyevent", "4")
        time.sleep(0.3)
        raw = dump()
        eds = [
            (int(a), int(b), int(c), int(d))
            for a, b, c, d in re.findall(
                r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
                raw,
            )
        ]
        log(f"eds={eds}")
        vals = ["demo", "demo%40gmail.com", "123456"]
        for i, v in enumerate(vals):
            if i >= len(eds):
                break
            a, b, c, d = eds[i]
            tap((a + c) // 2, (b + d) // 2)
            for _ in range(35):
                sh("shell", "input", "keyevent", "67")
            sh("shell", "input", "text", v)
            time.sleep(0.25)
            sh("shell", "input", "keyevent", "4")
            time.sleep(0.25)
        raw = dump()
        btns = re.findall(
            r'class="android.widget.Button"[^>]*content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        )
        log("btns=" + " ; ".join(f"{d}@{a},{b}-{c},{e}" for d, a, b, c, e in btns))
        tapped = False
        for desc, a, b, c, d in btns:
            if "Đăng nhập" in desc or "nhập" in desc and "Quên" not in desc:
                tap((int(a) + int(c)) // 2, (int(b) + int(d)) // 2)
                tapped = True
                log(f"tapped login {desc}")
                break
        if not tapped and btns:
            desc, a, b, c, d = btns[-1]
            tap((int(a) + int(c)) // 2, (int(b) + int(d)) // 2)
            log(f"tapped fallback {desc}")
        time.sleep(10)

    shot("c20-hub.png")
    raw = dump()
    descs = descs_of(raw)
    log("HUB: " + " | ".join(descs[:50]))

    # Open bottom tab "Nhiều hơn" if present
    for d in descs:
        if "Nhiều hơn" in d or "More" in d:
            m = re.search(
                rf'content-desc="{re.escape(d)}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
                raw,
            )
            if m:
                a, b, c, e = map(int, m.groups())
                tap((a + c) // 2, (b + e) // 2)
                log(f"opened more tab via {d}")
                time.sleep(2)
                break

    shot("c20-more.png")
    raw = dump()
    descs = descs_of(raw)
    log("MORE: " + " | ".join(descs[:60]))

    # Open Trung tâm Kho or Thiết lập POS
    for label in ("Trung tâm Kho", "Thiết lập POS", "Thiết lập HRM / POS", "Thiết lập"):
        m = re.search(
            rf'content-desc="{re.escape(label)}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        )
        if m:
            a, b, c, e = map(int, m.groups())
            tap((a + c) // 2, (b + e) // 2)
            log(f"opened {label}")
            time.sleep(3)
            shot("c20-settings-or-wh.png")
            raw2 = dump()
            log("OPENED: " + " | ".join(descs_of(raw2)[:50]))
            # back
            sh("shell", "input", "keyevent", "4")
            time.sleep(1)
            break

    # Try warehouse if we opened settings first
    raw = dump()
    m = re.search(
        r'content-desc="Trung tâm Kho"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        raw,
    )
    if m:
        a, b, c, e = map(int, m.groups())
        tap((a + c) // 2, (b + e) // 2)
        time.sleep(3)
        shot("c20-warehouse.png")
        log("WH: " + " | ".join(descs_of(dump())[:40]))

    log("DONE")


if __name__ == "__main__":
    main()
