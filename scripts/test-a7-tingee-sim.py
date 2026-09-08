# -*- coding: utf-8 -*-
"""A7 Tingee webhook simulation E2E test."""
from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request

ADB = r"adb"
SERIAL = "2637CCJ03256"
OUT = r"E:\SBOX CURSOR\ZKTecoADMS-master\.tmp-a7-tingee-test"
WEBHOOK_URL = "https://sboxhrm.com/api/webhooks/payment/tingee"
SECRET = "123456aA@"
CLIENT_ID = "b07c784a165ea8f8c70e4cb36e1b5cc3"
VA = "9935364556"
ORDER = "HD230820260009"
AMOUNT = 50000.0


def log(msg: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    print(msg)
    with open(os.path.join(OUT, "run.log"), "a", encoding="utf-8") as f:
        f.write(msg + "\n")


def sh(*args: str, timeout: int = 60) -> str:
    r = subprocess.run(
        [ADB, "-s", SERIAL, *args],
        capture_output=True,
        timeout=timeout,
    )
    out = (r.stdout or b"").decode("utf-8", "replace")
    err = (r.stderr or b"").decode("utf-8", "replace")
    if r.returncode != 0 and err.strip():
        log(f"ADB ERR ({args[0]}): {err.strip()}")
    return out + err


def dump(name: str) -> str:
    sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
    local = os.path.join(OUT, name)
    sh("pull", "/sdcard/ui.xml", local)
    if not os.path.exists(local):
        return ""
    return open(local, encoding="utf-8", errors="replace").read()


def shot(name: str) -> None:
    sh("shell", "screencap", "-p", "/sdcard/shot.png")
    sh("pull", "/sdcard/shot.png", os.path.join(OUT, name))


def tap(x: int, y: int) -> None:
    sh("shell", "input", "tap", str(x), str(y))
    time.sleep(0.5)


def tap_desc(raw: str, *needles: str) -> bool:
    for needle in needles:
        m = re.search(
            rf'content-desc="{re.escape(needle)}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        )
        if not m:
            m = re.search(
                rf'text="{re.escape(needle)}"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
                raw,
            )
        if m:
            a, b, c, d = map(int, m.groups())
            tap((a + c) // 2, (b + d) // 2)
            log(f"TAP {needle} @ {(a+c)//2},{(b+d)//2}")
            return True
    return False


def descs(raw: str) -> list[str]:
    ds = re.findall(r'content-desc="([^"]{2,120})"', raw)
    ts = re.findall(r'text="([^"]{2,120})"', raw)
    return ds + ts


def launch_hrm() -> None:
    sh("shell", "am", "force-stop", "sbox.sana.vn")
    time.sleep(0.5)
    sh(
        "shell",
        "am",
        "start",
        "-n",
        "sbox.sana.vn/vn.sana.sbox.MainActivity",
    )
    time.sleep(6)


def ensure_login() -> None:
    raw = dump("01-start.xml")
    joined = " ".join(descs(raw))
    log("START UI: " + " | ".join(descs(raw)[:25]))
    if any(k in joined for k in ("Đăng nhập", "CỬA HÀNG", "Quên mật khẩu", "EMAIL")):
        log("Login screen detected")
        eds = re.findall(
            r'class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
            raw,
        )
        vals = ["demopos", "demopos@gmail.com", "123456"]
        for i, v in enumerate(vals):
            if i >= len(eds):
                break
            a, b, c, d = map(int, eds[i])
            tap((a + c) // 2, (b + d) // 2)
            for _ in range(40):
                sh("shell", "input", "keyevent", "67")
            sh("shell", "input", "text", v.replace("@", "%40"))
            time.sleep(0.2)
        raw = dump("02-login.xml")
        if not tap_desc(raw, "Đăng nhập"):
            tap_desc(raw, "Login")
        time.sleep(10)
        shot("03-after-login.png")


def open_pos_transfer_confirm() -> None:
    raw = dump("04-hub.xml")
    log("HUB: " + " | ".join(descs(raw)[:30]))
    # Bottom nav POS
    for label in ("POS", "Bán hàng", "PosSell"):
        if tap_desc(raw, label):
            time.sleep(3)
            break
    raw = dump("05-pos.xml")
    log("POS: " + " | ".join(descs(raw)[:30]))
    # More menu
    for label in ("Nhiều hơn", "More", "Khác"):
        if tap_desc(raw, label):
            time.sleep(2)
            raw = dump("06-more.xml")
            break
    log("MORE: " + " | ".join(descs(raw)[:40]))
    for label in (
        "Xác nhận CK",
        "Xác nhận chuyển khoản",
        "Cổng thanh toán CK",
    ):
        if tap_desc(raw, label):
            time.sleep(3)
            shot("07-transfer-screen.png")
            log(f"Opened {label}")
            return
    shot("07-not-found.png")
    log("Could not open Xác nhận CK directly")


def sign(secret: str, timestamp: str, body: dict) -> str:
    raw = json.dumps(body, separators=(",", ":"))
    msg = f"{timestamp}:{raw}".encode()
    return hmac.new(secret.encode(), msg, hashlib.sha512).hexdigest().lower()


def fire_webhook() -> str:
    txn = f"SIM-{dt.datetime.now().strftime('%H%M%S')}"
    body = {
        "clientId": CLIENT_ID,
        "transactionCode": txn,
        "amount": AMOUNT,
        "content": f"Thanh toan {ORDER}",
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
        WEBHOOK_URL,
        data=raw.encode(),
        headers={
            "Content-Type": "application/json",
            "x-signature": sig,
            "x-request-timestamp": ts,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            text = resp.read().decode()
            log(f"WEBHOOK HTTP {resp.status}: {text}")
            return text
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        log(f"WEBHOOK HTTP {e.code}: {text}")
        return text


def verify_api() -> None:
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
        data = json.loads(resp.read().decode())
    token = data["data"]["accessToken"]
    hdr = {"Authorization": f"Bearer {token}"}
    for status in ("Waiting", "Confirmed"):
        url = (
            "https://sboxhrm.com/api/pos/payment-gateway/transfer-intents"
            f"?status={status}&limit=10"
        )
        req2 = urllib.request.Request(url, headers=hdr)
        with urllib.request.urlopen(req2, timeout=30) as resp:
            rows = json.loads(resp.read().decode()).get("data") or []
        hits = [
            r
            for r in rows
            if (r.get("externalOrderId") or r.get("orderNo")) == ORDER
        ]
        log(f"API {status} for {ORDER}: {hits}")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, "run.log"), "w", encoding="utf-8").write("")
    log("=== A7 Tingee simulation test ===")
    launch_hrm()
    ensure_login()
    open_pos_transfer_confirm()
    before = dump("08-before-webhook.xml")
    log("BEFORE WEBHOOK UI: " + " | ".join(descs(before)[:35]))
    shot("08-before-webhook.png")
    result = fire_webhook()
    time.sleep(4)
    after = dump("09-after-webhook.xml")
    log("AFTER WEBHOOK UI: " + " | ".join(descs(after)[:35]))
    shot("09-after-webhook.png")
    verify_api()
    ok = '"code":"00"' in result.replace(" ", "") or '"code": "00"' in result
    log(f"RESULT ok={ok}")
    if any(
        k in " ".join(descs(after))
        for k in ("Đã nhận", "chuyển khoản", "xác nhận", ORDER)
    ):
        log("UI shows payment confirmation cues")
    else:
        log("UI may not show toast yet — check screenshots")


if __name__ == "__main__":
    main()
