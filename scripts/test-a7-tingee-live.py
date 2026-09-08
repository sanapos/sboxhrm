# -*- coding: utf-8 -*-
"""Open Xác nhận CK on A7 and simulate Tingee webhook live."""
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
    time.sleep(0.7)


def texts(raw):
    return re.findall(r'content-desc="([^"]{2,160})"', raw) + re.findall(
        r'text="([^"]{2,160})"', raw
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


def login():
    sh("shell", "am", "start", "-n", "sbox.sana.vn/vn.sana.sbox.MainActivity")
    time.sleep(8)
    raw = dump("30.xml")
    if tap_text(raw, "Để sau"):
        time.sleep(2)
        raw = dump("31.xml")
    joined = " ".join(texts(raw))
    if "Đăng nhập" in joined or "Chào mừng" in joined:
        eds = re.findall(
            r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        )
        vals = ["demopos", "demopos%40gmail.com", "123456"]
        for i, v in enumerate(vals):
            if i >= len(eds):
                break
            a, b, c, d = map(int, eds[i])
            tap((a + c) // 2, (b + d) // 2)
            for _ in range(40):
                sh("shell", "input", "keyevent", "67")
            sh("shell", "input", "text", v)
            time.sleep(0.2)
        raw = dump("32.xml")
        tap_text(raw, "Đăng nhập")
        time.sleep(12)


def open_transfer_confirm():
    raw = dump("40-home.xml")
    print("HOME", " | ".join(texts(raw)[:20]))
    if tap_text(raw, "POS / Bán hàng"):
        time.sleep(2)
    raw = dump("41-poshub.xml")
    # bottom nav: Nhiều hơn
    for label in ("Nhiều hơn", "More"):
        if tap_text(raw, label):
            break
    else:
        # fallback bottom-right tab area
        tap(1750, 960)
    time.sleep(2)
    raw = dump("42-more.xml")
    print("MORE", " | ".join(texts(raw)[:30]))
    tap_text(raw, "Xác nhận CK")
    time.sleep(3)
    raw = dump("43-confirm.xml")
    print("CONFIRM", " | ".join(texts(raw)[:40]))
    return raw


def api_token():
    login = json.dumps(
        {
            "storeCode": "demopos",
            "userName": "demopos@gmail.com",
            "password": "123456",
        }
    ).encode()
    req = urllib.request.Request(
        "https://sboxhrm.com/api/auth/Login",
        data=login,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())["data"]["accessToken"]


def create_intent(order, amount):
    body = json.dumps(
        {
            "externalOrderId": order,
            "orderNo": order,
            "amountExpected": amount,
            "provider": "Tingee",
            "tableName": "Ngoài Sân · Bàn 02",
            "expireMinutes": 30,
        }
    ).encode()
    req = urllib.request.Request(
        "https://sboxhrm.com/api/pos/payment-gateway/transfer-intents",
        data=body,
        headers={
            "Authorization": f"Bearer {api_token()}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        print("INTENT", resp.read().decode())


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
    login()
    open_transfer_confirm()
    shot("43-confirm-before.png")
    order = f"SIM{dt.datetime.now().strftime('%H%M%S')}"
    amount = 88000
    create_intent(order, amount)
    time.sleep(2)
    raw = dump("44-refresh.xml")
    # refresh icon top-right ~ x=1850
    if not tap_text(raw, "refresh"):
        tap(1860, 110)
    time.sleep(2)
    raw = dump("45-waiting.xml")
    print("WAITING TAB", " | ".join(texts(raw)[:50]))
    shot("45-waiting.png")
    fire_webhook(order, amount)
    time.sleep(6)
    raw = dump("46-after.xml")
    print("AFTER", " | ".join(texts(raw)[:60]))
    shot("46-after.png")
    if any("Đã xác nhận" in t or order in t for t in texts(raw)):
        print("SUCCESS: order visible on device")
    elif any("Đã nhận" in t for t in texts(raw)):
        print("SUCCESS: notification visible")
    else:
        print("Check screenshots 45/46")


if __name__ == "__main__":
    main()
