# -*- coding: utf-8 -*-
"""A7: open table order -> Tingee payment -> simulate webhook -> capture UI."""
import re, subprocess, time, os, json, urllib.request, hashlib, hmac, datetime as dt

ADB = ["adb", "-s", "2637CCJ03256"]
OUT = r"E:\SBOX CURSOR\ZKTecoADMS-master\.tmp-a7-tingee-test"
SECRET = "123456aA@"
CLIENT_ID = "b07c784a165ea8f8c70e4cb36e1b5cc3"
VA = "9935364556"
WEBHOOK = "https://sboxhrm.com/api/webhooks/payment/tingee"


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


def ensure_pos_sell():
    sh("shell", "am", "start", "-n", "sbox.sana.vn/vn.sana.sbox.MainActivity")
    time.sleep(6)
    raw = dump("50.xml")
    if tap_text(raw, "Để sau"):
        time.sleep(2)
        raw = dump("51.xml")
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
        raw = dump("52.xml")
        tap_text(raw, "Đăng nhập")
        time.sleep(10)
    raw = dump("53.xml")
    if not any("Sơ đồ bàn" in t for t in texts(raw)):
        tap_text(raw, "Bán hàng") or tap_text(raw, "POS / Bán hàng")
        time.sleep(3)


def find_order_no(raw):
    for t in texts(raw):
        if re.match(r"HD\d+", t):
            return t
        if "HD" in t:
            m = re.search(r"HD\d+", t)
            if m:
                return m.group(0)
    return None


def sign(secret, timestamp, body):
    raw = json.dumps(body, separators=(",", ":"))
    msg = f"{timestamp}:{raw}".encode()
    return hmac.new(secret.encode(), msg, hashlib.sha512).hexdigest().lower()


def fire_webhook(order, amount):
    txn = f"SIM-{dt.datetime.now().strftime('%H%M%S')}"
    body = {
        "clientId": CLIENT_ID,
        "transactionCode": txn,
        "amount": amount,
        "content": f"Thanh toan {order}",
        "bank": "Vietcombank",
        "accountNumber": VA,
        "vaAccountNumber": VA,
        "transactionDate": dt.datetime.now().strftime("%Y%m%d%H%M%S"),
        "type": "credit",
    }
    raw = json.dumps(body, separators=(",", ":"))
    ts = dt.datetime.now().strftime("%Y%m%d%H%M%S") + "000"
    sig = sign(SECRET, ts, body)
    req = urllib.request.Request(
        WEBHOOK,
        data=raw.encode(),
        headers={
            "Content-Type": "application/json",
            "x-signature": sig,
            "x-request-timestamp": ts,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        text = resp.read().decode()
        print("WEBHOOK", resp.status, text)
        return text


def main():
    os.makedirs(OUT, exist_ok=True)
    ensure_pos_sell()
    raw = dump("60-floor.xml")
    print("FLOOR", " | ".join(texts(raw)[:25]))
    # close menu if open
    tap(960, 500)
    time.sleep(1)
    raw = dump("61-floor2.xml")
    tap_text(raw, "Bàn 03")
    time.sleep(3)
    raw = dump("62-table.xml")
    print("TABLE", " | ".join(texts(raw)[:40]))
    shot("62-table.png")
    order = find_order_no(raw)
    amount = 50000.0
    for t in texts(raw):
        if "đ" in t and any(ch.isdigit() for ch in t):
            m = re.search(r"([\d.,]+)", t.replace(".", ""))
            if m:
                try:
                    amount = float(m.group(1).replace(",", ""))
                except ValueError:
                    pass
    print("ORDER", order, "AMOUNT", amount)
    tap_text(raw, "Thanh toán") or tap_text(raw, "Thanh toán (F9)")
    time.sleep(3)
    raw = dump("63-pay.xml")
    print("PAY", " | ".join(texts(raw)[:50]))
    shot("63-pay.png")
    # select transfer / tingee
    for label in ("Chuyển khoản", "Tingee QR", "Tingee", "CK"):
        if tap_text(raw, label):
            break
    time.sleep(2)
    raw = dump("64-tingee.xml")
    print("TINGEE", " | ".join(texts(raw)[:50]))
    shot("64-tingee.png")
    order = find_order_no(raw) or order or f"SIM{dt.datetime.now().strftime('%H%M%S')}"
    print("FIRE FOR", order)
    fire_webhook(order, amount)
    time.sleep(6)
    raw = dump("65-success.xml")
    print("SUCCESS UI", " | ".join(texts(raw)[:60]))
    shot("65-success.png")
    joined = " ".join(texts(raw))
    if any(k in joined for k in ("Đã nhận", "chuyển khoản", "xác nhận", "Success")):
        print("PASS: device showed confirmation")
    else:
        print("Check 65-success.png")


if __name__ == "__main__":
    main()
