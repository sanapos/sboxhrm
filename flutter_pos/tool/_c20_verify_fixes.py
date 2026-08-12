# -*- coding: utf-8 -*-
import os
import re
import subprocess
import time

adb = r"C:\Users\TH DECOR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
s = "2637CCJ03256"
outdir = r"e:\SBOX CURSOR\ZKTecoADMS-master\.tmp-esp-audit"
logf = os.path.join(outdir, "c20-verify-fixes.log")


def log(msg):
    with open(logf, "a", encoding="utf-8") as f:
        f.write(msg + "\n")


def sh(*a):
    subprocess.run([adb, "-s", s, *a], capture_output=True)


def dump():
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    p = os.path.join(outdir, "c20-ui.xml")
    sh("pull", "/sdcard/ui.xml", p)
    return open(p, encoding="utf-8", errors="replace").read()


def tap(x, y):
    sh("shell", "input", "tap", str(x), str(y))
    time.sleep(0.6)


def shot(n):
    sh("shell", "screencap", "-p", "/sdcard/c20.png")
    sh("pull", "/sdcard/c20.png", os.path.join(outdir, n))


def find(raw, needle):
    for m in re.finditer(
        r'content-desc="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        raw,
    ):
        if needle in m.group(1):
            a, b, c, d = map(int, m.groups()[1:])
            return (a + c) // 2, (b + d) // 2, m.group(1)
    return None


open(logf, "w", encoding="utf-8").write("")
sh("shell", "am", "force-stop", "sbox.sana.vn.pos.flutter")
sh(
    "shell",
    "am",
    "start",
    "-n",
    "sbox.sana.vn.pos.flutter/vn.sana.sbox.sbox_pos.MainActivity",
)
time.sleep(4)
raw = dump()
if find(raw, "Phòng") or find(raw, "Thực"):
    tap(42, 72)
    time.sleep(1.2)
    raw = dump()
more = find(raw, "Nhiều hơn")
tap(*(more[:2] if more else (1728, 960)))
time.sleep(1.2)
raw = dump()

# Settings via gear
st = find(raw, "Cài đặt")
if st:
    tap(*st[:2])
    log(f"settings {st[2]}")
else:
    prof = find(raw, "Owner")
    if prof:
        # settings is left of logout — approx
        # find buttons near profile y
        tap(prof[0] + 700 if False else 1750, 180)
        log("settings geometric")
time.sleep(2)
shot("c20-settings-v2.png")
raw = dump()
descs = re.findall(r'content-desc="([^"]{2,50})"', raw)
log("SETTINGS: " + " | ".join(descs[:35]))
# swipe up to see printer modules
sh("shell", "input", "swipe", "960", "850", "960", "250", "400")
time.sleep(1)
shot("c20-settings-scrolled.png")
raw = dump()
log("SCROLLED: " + " | ".join(re.findall(r'content-desc="([^"]{2,40})"', raw)[:30]))

# open Máy in if visible
printer = find(raw, "Máy in")
if printer:
    tap(*printer[:2])
    time.sleep(2)
    shot("c20-printer-hub.png")
    raw = dump()
    log("PRINTER: " + " | ".join(re.findall(r'content-desc="([^"]{2,50})"', raw)[:25]))
    # swipe to see agent
    sh("shell", "input", "swipe", "960", "850", "960", "200", "400")
    time.sleep(0.8)
    shot("c20-printer-agent.png")
    log("AGENT: " + " | ".join(re.findall(r'content-desc="([^"]{2,50})"', dump())[:25]))

# back to more, logout
for _ in range(3):
    sh("shell", "input", "keyevent", "4")
    time.sleep(0.5)
raw = dump()
if not find(raw, "Nhiều hơn") and not find(raw, "Owner"):
    tap(1728, 960)
    time.sleep(1)
    raw = dump()
lo = find(raw, "Đăng xuất")
if lo:
    tap(*lo[:2])
else:
    # IconButtons: last on profile row
    btns = [
        tuple(map(int, m.groups()))
        for m in re.finditer(
            r'class="android.widget.Button"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        )
    ]
    top = [b for b in btns if 100 < b[1] < 280 and b[0] > 1500]
    log(f"logout candidates {top}")
    if top:
        g = sorted(top, key=lambda t: t[0])[-1]
        tap((g[0] + g[2]) // 2, (g[1] + g[3]) // 2)
    else:
        tap(1860, 180)
time.sleep(1.2)
raw = dump()
log("LOGOUT_DLG: " + " | ".join(re.findall(r'content-desc="([^"]{2,40})"', raw)[:15]))
confirms = list(
    re.finditer(
        r'content-desc="Đăng xuất"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        raw,
    )
)
if confirms:
    a, b, c, d = map(int, confirms[-1].groups())
    tap((a + c) // 2, (b + d) // 2)
else:
    # dialog button by text node class Button near bottom center
    for m in re.finditer(
        r'class="android.widget.Button"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        raw,
    ):
        a, b, c, d = map(int, m.groups())
        if b > 400:
            tap((a + c) // 2, (b + d) // 2)
            break
time.sleep(3)
shot("c20-logout-v2.png")
raw = dump()
log("AFTER_LOGOUT: " + " | ".join(re.findall(r'content-desc="([^"]{2,40})"', raw)[:20]))
log("DONE")
print(open(logf, encoding="utf-8").read())
