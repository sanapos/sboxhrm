# -*- coding: utf-8 -*-
import os
import re
import subprocess
import time

adb = r"C:\Users\TH DECOR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
s = "2637CCJ03256"
outdir = r"e:\SBOX CURSOR\ZKTecoADMS-master\.tmp-esp-audit"


def sh(*a):
    return subprocess.run([adb, "-s", s, *a], capture_output=True)


def dump():
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    p = os.path.join(outdir, "c20-ui.xml")
    sh("pull", "/sdcard/ui.xml", p)
    return open(p, encoding="utf-8", errors="replace").read()


def tap(x, y):
    sh("shell", "input", "tap", str(x), str(y))
    time.sleep(0.7)


def shot(name):
    sh("shell", "screencap", "-p", "/sdcard/c20.png")
    sh("pull", "/sdcard/c20.png", os.path.join(outdir, name))


# Ensure on More
sh("shell", "input", "keyevent", "4")
time.sleep(0.5)
sh("shell", "input", "keyevent", "4")
time.sleep(0.5)
tap(42, 72)
time.sleep(1)
raw = dump()
m = re.search(
    r'content-desc="([^"]*Nhi[^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    raw,
)
if m:
    tap((int(m.group(2)) + int(m.group(4))) // 2, (int(m.group(3)) + int(m.group(5))) // 2)
else:
    tap(1728, 960)
time.sleep(1.2)
raw = dump()
# logout tooltip
m = re.search(
    r'content-desc="Đăng xuất"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    raw,
)
log = []
if m:
    log.append(f"logout btn {m.groups()}")
    tap((int(m.group(1)) + int(m.group(3))) // 2, (int(m.group(2)) + int(m.group(4))) // 2)
else:
    # right icons on profile
    prof = re.search(
        r'content-desc="[^"]*Owner[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        raw,
    )
    if prof:
        a, b, c, d = map(int, prof.groups())
        tap(c - 50, (b + d) // 2)
        log.append(f"logout geometric {c-50}")
    else:
        tap(1840, 180)
        log.append("logout fallback 1840,180")
time.sleep(1.2)
raw = dump()
log.append("DIALOG: " + " | ".join(re.findall(r'content-desc="([^"]{2,40})"', raw)[:20]))
hits = list(
    re.finditer(
        r'content-desc="Đăng xuất"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        raw,
    )
)
if hits:
    a, b, c, d = map(int, hits[-1].groups())
    tap((a + c) // 2, (b + d) // 2)
    log.append("confirmed logout")
else:
    # FilledButton may expose text differently — tap right side of dialog
    tap(1100, 620)
    log.append("confirm geometric")
time.sleep(3)
shot("c20-after-logout.png")
raw = dump()
log.append("AFTER: " + " | ".join(re.findall(r'content-desc="([^"]{2,50})"', raw)[:20]))
open(os.path.join(outdir, "c20-logout-check.txt"), "w", encoding="utf-8").write(
    "\n".join(log)
)
print("\n".join(log))
