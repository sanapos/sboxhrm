# -*- coding: utf-8 -*-
"""Open demopos POS on A7 -> Bàn 03 -> Thanh toán Tingee QR for real CK test."""
import re, subprocess, time, os

ADB = ["adb", "-s", "2637CCJ03256"]
OUT = r"E:\SBOX CURSOR\ZKTecoADMS-master\.tmp-a7-tingee-test"


def sh(*a):
    subprocess.run(ADB + list(a), capture_output=True)


def dump(n):
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    p = os.path.join(OUT, n)
    sh("pull", "/sdcard/ui.xml", p)
    return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""


def shot(n):
    sh("shell", "screencap", "-p", "/sdcard/shot.png")
    sh("pull", "/sdcard/shot.png", os.path.join(OUT, n))


def tap(x, y):
    sh("shell", "input", "tap", str(x), str(y))
    time.sleep(0.8)


def texts(raw):
    return re.findall(r'content-desc="([^"]{2,200})"', raw) + re.findall(
        r'text="([^"]{2,200})"', raw
    )


def tap_text(raw, needle):
    for pat in (
        rf'content-desc="{re.escape(needle)}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
        rf'text="{re.escape(needle)}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    ):
        m = re.search(pat, raw)
        if m:
            a, b, c, d = map(int, m.groups())
            tap((a + c) // 2, (b + d) // 2)
            print("TAP", needle)
            return True
    return False


def main():
    os.makedirs(OUT, exist_ok=True)
    sh("shell", "am", "start", "-n", "sbox.sana.vn/vn.sana.sbox.MainActivity")
    time.sleep(6)
    raw = dump("real-01.xml")
    if tap_text(raw, "Để sau"):
        time.sleep(1)
    raw = dump("real-02.xml")
    if "Đăng nhập" in " ".join(texts(raw)):
        eds = re.findall(
            r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        )
        for i, v in enumerate(["demopos", "demopos%40gmail.com", "123456"]):
            if i >= len(eds):
                break
            a, b, c, d = map(int, eds[i])
            tap((a + c) // 2, (b + d) // 2)
            for _ in range(40):
                sh("shell", "input", "keyevent", "67")
            sh("shell", "input", "text", v)
        tap_text(dump("real-03.xml"), "Đăng nhập")
        time.sleep(10)
    raw = dump("real-04.xml")
    tap_text(raw, "Bán hàng") or tap_text(raw, "POS / Bán hàng")
    time.sleep(3)
    raw = dump("real-05.xml")
    # close menu overlay if any
    tap(960, 500)
    time.sleep(0.5)
    raw = dump("real-06.xml")
    tap_text(raw, "Bàn 03")
    time.sleep(3)
    raw = dump("real-07-table.xml")
    print("TABLE", " | ".join(texts(raw)[:40]))
    shot("real-07-table.png")
    tap_text(raw, "Thanh toán") or tap_text(raw, "Thanh toán (F9)")
    time.sleep(3)
    raw = dump("real-08-pay.xml")
    print("PAY", " | ".join(texts(raw)[:50]))
    for label in ("Chuyển khoản", "Tingee QR", "Tingee"):
        if tap_text(raw, label):
            break
    time.sleep(2)
    raw = dump("real-09-tingee.xml")
    print("TINGEE", " | ".join(texts(raw)[:60]))
    shot("real-09-tingee-payment.png")
    for t in texts(raw):
        if "HD" in t or "đ" in t:
            print("INFO", t)


if __name__ == "__main__":
    main()
