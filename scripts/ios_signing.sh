#!/usr/bin/env bash
# Ký app iOS trên Codemagic cho $BUNDLE_ID, giống các workflow iOS hiện có.
# Thu hồi chứng chỉ Distribution cũ nên mỗi lần chỉ chạy một build iOS.
set -euo pipefail

if [ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ] || [ -z "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" ] || [ -z "${APP_STORE_CONNECT_PRIVATE_KEY:-}" ]; then
  echo "ERROR: Missing APP_STORE_CONNECT_* env vars (group appstore_credentials)."
  exit 1
fi

python3 <<'PY'
import json
import subprocess
import sys

seen = set()
for cert_type in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
    listed = subprocess.run(
        ["app-store-connect", "certificates", "list", "--type", cert_type, "--json"],
        capture_output=True, text=True, check=True,
    )
    payload = json.loads(listed.stdout or "[]")
    items = payload if isinstance(payload, list) else payload.get("certificates") or payload.get("data") or []
    for item in items:
        cert_id = item.get("id") or item.get("Id")
        if cert_id and cert_id not in seen:
            seen.add(cert_id)
            subprocess.run(["app-store-connect", "certificates", "delete", cert_id], check=True)
print(f"Revoked {len(seen)} distribution certificate(s)")
PY
sleep 5

CERT_KEY=$(mktemp)
openssl genrsa -out "$CERT_KEY" 2048
app-store-connect fetch-signing-files "$BUNDLE_ID" \
  --type IOS_APP_STORE \
  --platform IOS \
  --certificate-key "@file:$CERT_KEY" \
  --create
keychain initialize
keychain add-certificates
xcode-project use-profiles
rm -f "$CERT_KEY"
