# -*- coding: utf-8 -*-
import os
import re
import subprocess
import time

adb = r"C:\Users\TH DECOR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
s = "V329221L21176"
outdir = r"e:\SBOX CURSOR\ZKTecoADMS-master\.tmp-esp-audit"


def sh(*a):
    r = subprocess.run([adb, "-s", s, *a], capture_output=True)
    return (r.stdout or b"").decode("utf-8", "replace") + (
        r.stderr or b""
    ).decode("utf-8", "replace")


def dump():
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    p = os.path.join(outdir, "v2s-ui.xml")
    sh("pull", "/sdcard/ui.xml", p)
    return open(p, encoding="utf-8", errors="replace").read()


def shot(name):
    sh("shell", "screencap", "-p", "/sdcard/v2s.png")
    sh("pull", "/sdcard/v2s.png", os.path.join(outdir, name))


# Force natural portrait (rotation 0)
sh("shell", "settings", "put", "system", "accelerometer_rotation", "0")
sh("shell", "settings", "put", "system", "user_rotation", "0")
time.sleep(1)
raw = dump()
m = re.search(r'bounds="\[0,0\]\[(\d+),(\d+)\]"', raw)
print("root", m.groups() if m else None)
descs = re.findall(r'content-desc="([^"]{2,50})"', raw)
print("DESC:", " | ".join(descs[:30]))
shot("v2s-current.png")
# Rotate to landscape then back to see lock
sh("shell", "settings", "put", "system", "user_rotation", "1")
time.sleep(1.5)
raw = dump()
m = re.search(r'bounds="\[0,0\]\[(\d+),(\d+)\]"', raw)
print("rot1 root", m.groups() if m else None)
shot("v2s-rot1.png")
sh("shell", "settings", "put", "system", "user_rotation", "0")
time.sleep(1)
print("done")
