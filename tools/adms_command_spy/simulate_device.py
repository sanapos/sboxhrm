#!/usr/bin/env python3
"""Simulate ZKTeco PUSH device to drain ADMS commands from a cloud server."""

from __future__ import annotations

import argparse
import ssl
import time
import urllib.error
import urllib.request
from datetime import datetime

CTX = ssl.create_default_context()


def ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


def req(method: str, url: str, body: bytes | None = None, timeout: int = 30) -> tuple[int, str]:
    headers = {
        "User-Agent": "iClock Proxy/1.09",
        "Accept": "*/*",
        "Connection": "close",
    }
    if body is not None:
        headers["Content-Type"] = "text/plain;charset=UTF-8"
        headers["Content-Length"] = str(len(body))
    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, context=CTX, timeout=timeout) as resp:
            raw = resp.read()
            text = raw.decode("utf-8", errors="replace")
            return resp.status, text
    except urllib.error.HTTPError as e:
        raw = e.read() or b""
        return e.code, raw.decode("utf-8", errors="replace")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--base", default="https://sana.zkbiotimecloud.com", help="ADMS base URL")
    p.add_argument("--sn", default="1313254901006")
    p.add_argument("--rounds", type=int, default=20)
    p.add_argument("--delay", type=float, default=2.0)
    p.add_argument("--ack", action="store_true", help="ACK commands with Return=0")
    args = p.parse_args()
    base = args.base.rstrip("/")
    sn = args.sn

    print(f"[{ts()}] Simulate SN={sn} -> {base}")

    url = f"{base}/iclock/cdata?SN={sn}&options=all&language=86&pushver=2.4.1&DeviceType=att&PushOptionsFlag=1"
    code, text = req("GET", url)
    print(f"[{ts()}] GET options=all => {code}\n{text[:800]}\n")

    # SenseFace-like options body (comma-separated), same SN as real device
    options_body = (
        "~DeviceName=SenseFace 2A,MAC=00:17:61:11:71:d0,TransactionCount=4,~MaxAttLogCount=15,"
        "UserCount=2,~MaxUserCount=30,PhotoFunOn=1,~MaxUserPhotoCount=3000,FingerFunOn=1,FPVersion=10,"
        "~MaxFingerCount=30,FPCount=1,FaceFunOn=1,FaceVersion=40,~MaxFaceCount=1500,FaceCount=1,"
        "Language=86,IPAddress=192.168.1.15,~Platform=ZAM70_TFT,~OEMVendor=ZKTECO CO., LTD.,"
        "FWVersion=ZAM70-NF24HA-3.3.12-OCM-2535-Ver1.1.0,PushVersion=Ver 3.1.2S-20250616,"
        "VisilightFun=1,~LockFunOn=1"
    ).encode("utf-8")
    code, text = req("POST", f"{base}/iclock/cdata?SN={sn}&table=options", options_body)
    print(f"[{ts()}] POST options => {code} {text[:200]!r}")

    for i in range(1, args.rounds + 1):
        for path in ("getrequest", "ping"):
            code, text = req("GET", f"{base}/iclock/{path}?SN={sn}")
            body = (text or "").strip()
            interesting = body and body.upper() != "OK"
            mark = "***" if interesting else "   "
            print(f"[{ts()}] {mark} {i:02d} GET /{path} => {code} {body[:300]!r}")
            if interesting and args.ack:
                # Parse C:ID:CMD lines and ACK
                for line in body.splitlines():
                    line = line.strip()
                    if not line.startswith("C:"):
                        continue
                    parts = line.split(":", 2)
                    if len(parts) < 3:
                        continue
                    cmd_id, cmd = parts[1], parts[2]
                    cmd_name = cmd.split()[0] if cmd else "UNKNOWN"
                    ack = f"ID={cmd_id}&Return=0&CMD={cmd_name}\n".encode("utf-8")
                    ac, at = req("POST", f"{base}/iclock/devicecmd?SN={sn}", ack)
                    print(f"[{ts()}]     ACK {cmd_id}/{cmd_name} => {ac} {at[:80]!r}")
        time.sleep(args.delay)

    print(f"[{ts()}] Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
