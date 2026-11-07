#!/usr/bin/env bash
# Ký app iOS trên Codemagic cho $BUNDLE_ID. Tham số 1: loại hồ sơ, mặc định IOS_APP_STORE.
# Dùng khóa cố định CERTIFICATE_PRIVATE_KEY (Secure, nhóm appstore_credentials) để mọi build dùng chung một chứng chỉ.
# Tuyệt đối không thu hồi chứng chỉ ở đây: bản đang chờ Apple duyệt được ký bằng chứng chỉ đó.
set -euo pipefail

PROFILE_TYPE="${1:-IOS_APP_STORE}"

if [ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ] || [ -z "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" ] || [ -z "${APP_STORE_CONNECT_PRIVATE_KEY:-}" ]; then
  echo "ERROR: Missing APP_STORE_CONNECT_* env vars (group appstore_credentials)."
  exit 1
fi
if [ -z "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
  echo "ERROR: Missing CERTIFICATE_PRIVATE_KEY (Secure, group appstore_credentials)."
  exit 1
fi

app-store-connect fetch-signing-files "$BUNDLE_ID" \
  --type "$PROFILE_TYPE" \
  --platform IOS \
  --certificate-key "@env:CERTIFICATE_PRIVATE_KEY" \
  --create
keychain initialize
keychain add-certificates
xcode-project use-profiles
