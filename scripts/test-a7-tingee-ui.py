# -*- coding: utf-8 -*-
import re, subprocess, time, os, json, urllib.request, hashlib, hmac, datetime as dt

ADB = ["adb", "-s", "2637CCJ03256"]
OUT = r"E:\SBOX CURSOR\ZKTecoADMS-master\.tmp-a7-tingee-test"
SECRET = "123456aA@"
CLIENT_ID = "b07c784a165ea8f8c70e4cb36e1b5cc3"
VA = "9935364556"
WEBHOOK = "https://sboxhrm.com/api/webhooks/payment/tingee"


def sh(*a):
    r = subprocess.run(ADB + list(a), capture_output=True)
    return (r.stdout or b"").decode("utf-8", "replace")


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
    time.sleep(0.6)


def texts(raw):
    return re.findall(r'content-desc="([^"]{2,120})"', raw) + re.findall(
        r'text="([^"]{2,120})"', raw
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
            print(f"TAP {needle}")
            return True
    return False


def dismiss_permissions(raw):
    if tap_text(raw, "Để sau"):
        time.sleep(2)
        return dump("11b-perms.xml")
    if tap_text(raw, "Cấp quyền"):
        time.sleep(3)
        # auto-grant dialogs
        for _ in range(5):
            raw2 = dump("11c-perm-dialog.xml")
            if tap_text(raw2, "Cho phép") or tap_text(raw2, "Allow") or tap_text(
                raw2, "WHILE USING THE APP"
            ):
                time.sleep(1)
            else:
                break
        return dump("11d-after-perms.xml")
    return raw


def login_if_needed(raw):
    joined = " ".join(texts(raw))
    if not any(k in joined for k in ("Đăng nhập", "CỬA HÀNG", "Quên mật khẩu")):
        return raw
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
        time.sleep(0.2)
    raw = dump("12-login.xml")
    tap_text(raw, "Đăng nhập")
    time.sleep(12)
    return dump("13-home.xml")


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


def create_intent(order, amount):
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
        token = json.loads(resp.read().decode())["data"]["accessToken"]
    body = json.dumps(
        {
            "externalOrderId": order,
            "orderNo": order,
            "amountExpected": amount,
            "provider": "Tingee",
            "expireMinutes": 30,
        }
    ).encode()
    req2 = urllib.request.Request(
        "https://sboxhrm.com/api/pos/payment-gateway/transfer-intents",
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req2, timeout=30) as resp:
        data = json.loads(resp.read().decode())
        print("INTENT", data)


def main():
    os.makedirs(OUT, exist_ok=True)
    sh("shell", "input", "keyevent", "3")
    time.sleep(1)
    sh(
        "shell",
        "monkey",
        "-p",
        "sbox.sana.vn",
        "-c",
        "android.intent.category.LAUNCHER",
        "1",
    )
    time.sleep(8)
    raw = dump("11-app.xml")
    print("APP:", " | ".join(texts(raw)[:25]))
    raw = dismiss_permissions(raw)
    raw = login_if_needed(raw)
    print("HOME:", " | ".join(texts(raw)[:30]))
    for label in ("POS", "Bán hàng", "PosSell", "Thu ngân"):
        if tap_text(raw, label):
            break
    time.sleep(4)
    raw = dump("14-pos.xml")
    print("POS:", " | ".join(texts(raw)[:35]))
    for label in ("Nhiều hơn", "More", "Khác"):
        if tap_text(raw, label):
            break
    time.sleep(2)
    raw = dump("15-more.xml")
    print("MORE:", " | ".join(texts(raw)[:40]))
    for label in ("Xác nhận CK", "Xác nhận chuyển khoản"):
        if tap_text(raw, label):
            break
    time.sleep(3)
    raw = dump("16-confirm-before.xml")
    print("CONFIRM BEFORE:", " | ".join(texts(raw)[:50]))
    shot("16-confirm-before.png")

    order = f"SIM{dt.datetime.now().strftime('%H%M%S')}"
    create_intent(order, 75000)
    time.sleep(1)
    # refresh
    tap_text(raw, "refresh") or tap(1850, 120)
    time.sleep(2)
    raw = dump("17-confirm-waiting.xml")
    print("CONFIRM WAITING:", " | ".join(texts(raw)[:50]))

    fire_webhook(order, 75000)
    time.sleep(5)
    raw = dump("18-confirm-after.xml")
    print("CONFIRM AFTER:", " | ".join(texts(raw)[:60]))
    shot("18-confirm-after.png")


if __name__ == "__main__":
    main()
