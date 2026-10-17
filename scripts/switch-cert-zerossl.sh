#!/bin/bash
# Đổi chứng chỉ HTTPS của một tên miền từ Let's Encrypt sang ZeroSSL.
#
# Vì sao: Android 6 trở xuống (Sunmi T1, Chrome 56) không tin gốc ISRG của Let's Encrypt →
# «Kết nối của bạn không phải là kết nối riêng tư». ZeroSSL nối về gốc USERTrust RSA (Sectigo),
# có sẵn trên Android 6 (đã kiểm tra trên T1: /system/etc/security/cacerts/35105088.0).
#
# Chạy trên máy chủ (root), mỗi tên miền một lần:
#   ssh root@103.133.224.176 'bash -s' < scripts/switch-cert-zerossl.sh sboxhrm.com you@example.com
#   ssh root@103.133.225.67  'bash -s' < scripts/switch-cert-zerossl.sh sboxpos.com you@example.com
#
# Lần đầu với một email, API ZeroSSL tự tạo / gắn tài khoản ZeroSSL với email đó và trả khóa EAB.
# certbot lưu tài khoản ACME + webroot vào /etc/letsencrypt/renewal/<domain>.conf → tự gia hạn như cũ.
set -euo pipefail

DOMAIN="${1:?Thiếu tên miền, vd sboxhrm.com}"
EMAIL="${2:?Thiếu email nhận thông báo ZeroSSL}"
WEBROOT="${WEBROOT:-/var/www/html}"

echo "==> Lấy khóa EAB ZeroSSL cho $EMAIL"
EAB_JSON=$(curl -fsS https://api.zerossl.com/acme/eab-credentials-email --data-urlencode "email=$EMAIL")
EAB_KID=$(printf '%s' "$EAB_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["eab_kid"])')
EAB_HMAC=$(printf '%s' "$EAB_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["eab_hmac_key"])')

echo "==> Sao lưu chứng chỉ Let's Encrypt hiện tại"
tar -czf "/root/letsencrypt-backup-$DOMAIN-$(date +%Y%m%d-%H%M%S).tar.gz" /etc/letsencrypt

echo "==> Xin chứng chỉ ZeroSSL cho $DOMAIN, www.$DOMAIN (webroot $WEBROOT)"
certbot certonly --non-interactive --agree-tos --no-eff-email -m "$EMAIL" \
  --server https://acme.zerossl.com/v2/DV90 \
  --eab-kid "$EAB_KID" --eab-hmac-key "$EAB_HMAC" \
  --webroot -w "$WEBROOT" \
  --cert-name "$DOMAIN" -d "$DOMAIN" -d "www.$DOMAIN" \
  --key-type rsa --force-renewal

nginx -t
systemctl reload nginx

echo "==> Chuỗi chứng chỉ đang phục vụ:"
echo | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null | grep -E '^ *[0-9] s:|i:'
echo "XONG $DOMAIN"
