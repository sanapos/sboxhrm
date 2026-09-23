#!/usr/bin/env python3
"""Point SBOX POS App Review at the demopos cashier that exists on sboxpos.com.

Apple was given demo@gmail.com. That account is not in store demopos, so review
login fails with "Tài khoản không tồn tại trong cửa hàng này."
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

APP_ID = os.environ.get("APP_STORE_APP_ID", "6807833339")
USERNAME = os.environ.get("APP_REVIEW_USERNAME", "demopos@gmail.com")
PASSWORD = os.environ.get("APP_REVIEW_PASSWORD", "123456")
NOTES = os.environ.get(
    "APP_REVIEW_NOTES",
    "\n".join(
        [
            "SBOX POS is a cloud cash register for shops that already have a store on https://sboxpos.com.",
            "The iOS app is locked to that server. There is no server-address field.",
            "Sign in with:",
            "  Store code: demopos",
            "  Username: demopos@gmail.com",
            "  Password: 123456",
            "demo@gmail.com is accepted as the same cashier.",
            "Open Ban hang to sell. No in-app purchase. Staff accounts are created by the shop, not inside the App Store app.",
            "The first-launch note has one button, Continue. It always opens the iOS camera and location permission dialogs. There is no Grant or Later button.",
            "Privacy: https://sboxpos.com/privacy-policy.html",
            "Support: support@sboxhrm.com  +84 973 024 042",
        ]
    ),
)


def b64(raw: bytes) -> bytes:
    return base64.urlsafe_b64encode(raw).rstrip(b"=")


def der_to_raw(der: bytes) -> bytes:
    if der[0] != 0x30:
        raise SystemExit("ES256 signature is not DER")
    i = 2
    if der[1] & 0x80:
        i = 2 + (der[1] & 0x7F)

    def read_int(buf: bytes, idx: int) -> tuple[bytes, int]:
        if buf[idx] != 0x02:
            raise SystemExit("bad INTEGER in signature")
        ln = buf[idx + 1]
        idx += 2
        val = buf[idx : idx + ln]
        idx += ln
        if len(val) > 32:
            val = val[-32:]
        return val.rjust(32, b"\x00"), idx

    r, i = read_int(der, i)
    s, _ = read_int(der, i)
    return r + s


def token() -> str:
    kid = os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]
    iss = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
    pem = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].replace("\\n", "\n")
    if "BEGIN" not in pem:
        pem = base64.b64decode(pem).decode()
    now = int(time.time())
    header = b64(json.dumps({"alg": "ES256", "kid": kid, "typ": "JWT"}).encode())
    payload = b64(
        json.dumps(
            {"iss": iss, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
        ).encode()
    )
    signing = header + b"." + payload
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".p8") as fh:
        fh.write(pem if pem.endswith("\n") else pem + "\n")
        key_path = fh.name
    try:
        der = subprocess.check_output(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=signing,
        )
    finally:
        os.remove(key_path)
    return (signing + b"." + b64(der_to_raw(der))).decode()


class ApiError(Exception):
    def __init__(self, code: int, detail: str):
        super().__init__(f"{code} {detail[:800]}")
        self.code = code
        self.detail = detail


def api(method: str, path: str, body: dict | None, jwt: str) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {jwt}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode()
    except urllib.error.HTTPError as ex:
        detail = ex.read().decode("utf-8", "replace")
        raise ApiError(ex.code, detail)
    return json.loads(raw) if raw else {}


REVIEW_ATTRS = {
    "demoAccountRequired": True,
    "demoAccountName": USERNAME,
    "demoAccountPassword": PASSWORD,
    "notes": NOTES,
    "contactFirstName": "Linh",
    "contactLastName": "Nguyen",
    "contactEmail": "sanapos.vn@gmail.com",
    "contactPhone": "+84973024042",
}

# Prefer a version Apple can still attach review notes to.
_EDITABLE_STATES = (
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
)


def pick_version(versions: list[dict]) -> dict:
    for state in _EDITABLE_STATES:
        for version in versions:
            if (version.get("attributes") or {}).get("appStoreState") == state:
                return version
    if not versions:
        raise SystemExit("No iOS App Store version found for this app")
    return versions[0]


def main() -> None:
    jwt = token()
    # Review details hang off the App Store version, not the app.
    listed = api(
        "GET",
        f"/v1/apps/{APP_ID}/appStoreVersions?filter[platform]=IOS&limit=20",
        None,
        jwt,
    )
    version = pick_version(listed.get("data") or [])
    version_id = version["id"]
    attrs = version.get("attributes") or {}
    print(
        "Using App Store version"
        f" {attrs.get('versionString')} state={attrs.get('appStoreState')} id={version_id}"
    )

    try:
        existing = api(
            "GET",
            f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail",
            None,
            jwt,
        )
    except ApiError as ex:
        if ex.code != 404:
            raise SystemExit(f"App Store Connect GET review detail -> {ex}")
        existing = {}

    review = existing.get("data") if isinstance(existing, dict) else None
    if review and review.get("id"):
        review_id = review["id"]
        patched = api(
            "PATCH",
            f"/v1/appStoreReviewDetails/{review_id}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": review_id,
                    "attributes": REVIEW_ATTRS,
                }
            },
            jwt,
        )
    else:
        patched = api(
            "POST",
            "/v1/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": REVIEW_ATTRS,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        }
                    },
                }
            },
            jwt,
        )
    name = patched.get("data", {}).get("attributes", {}).get("demoAccountName")
    print(f"Updated App Review demo account to {name} for app {APP_ID}")


if __name__ == "__main__":
    main()
