#!/usr/bin/env python3
"""Mô phỏng webhook Tingee → Sbox (Payment Callback).

Usage:
  python scripts/test-tingee-webhook.py --secret YOUR_WEBHOOK_SECRET \\
    --client-id YOUR_CLIENT_ID --va 9935364556 --amount 50000 --order TMP999

Docs: https://developers.tingee.vn/docs/webhook/webhook-payment-callback/
UAT portal: https://uat-baas-portal.tingee.vn
UAT API: https://uat-open-api.tingee.vn/v1
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import hmac
import json
import urllib.error
import urllib.request


def sign(secret: str, timestamp: str, body: dict) -> str:
    raw = json.dumps(body, separators=(",", ":"))
    msg = f"{timestamp}:{raw}".encode()
    return hmac.new(secret.encode(), msg, hashlib.sha512).hexdigest().lower()


def main() -> None:
    p = argparse.ArgumentParser(description="Test Tingee webhook to Sbox")
    p.add_argument("--url", default="https://sboxhrm.com/api/webhooks/payment/tingee")
    p.add_argument("--secret", required=True)
    p.add_argument("--client-id", required=True)
    p.add_argument("--va", required=True, help="vaAccountNumber")
    p.add_argument("--amount", type=float, default=1000)
    p.add_argument("--order", default="TMPTEST001", help="External order id in content")
    p.add_argument("--txn", default=None, help="transactionCode (auto if omitted)")
    args = p.parse_args()

    txn = args.txn or f"TEST-{dt.datetime.now().strftime('%H%M%S')}"
    body = {
        "clientId": args.client_id,
        "transactionCode": txn,
        "amount": args.amount,
        "content": f"Thanh toan {args.order}",
        "bank": "Vietcombank",
        "accountNumber": args.va,
        "vaAccountNumber": args.va,
        "transactionDate": dt.datetime.now().strftime("%Y%m%d%H%M%S"),
        "type": "credit",
    }
    raw = json.dumps(body, separators=(",", ":"))
    ts = dt.datetime.now().strftime("%Y%m%d%H%M%S") + "000"
    sig = sign(args.secret, ts, body)

    req = urllib.request.Request(
        args.url,
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
            print("HTTP", resp.status)
            print(resp.read().decode())
    except urllib.error.HTTPError as e:
        print("HTTP", e.code)
        print(e.read().decode())


if __name__ == "__main__":
    main()
