#!/bin/bash
# First-time host setup for sboxpos.com (Ubuntu 22.04) — same stack as sboxhrm.com
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== 1. Packages (curl, nginx, certbot, ufw) ==="
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release nginx certbot python3-certbot-nginx ufw

echo "=== 2. Docker ==="
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
docker --version
docker compose version

echo "=== 3. Firewall ==="
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable || true
ufw status || true

echo "=== 4. Directories ==="
mkdir -p /opt/zkteco/secrets /opt/zkteco/gc /var/www/html/.well-known/acme-challenge
if [ ! -s /opt/zkteco/secrets/fcm-service-account.json ]; then
  printf '%s\n' '{}' > /opt/zkteco/secrets/fcm-service-account.json
fi
# API container runs as uid 1654 — file must be world-readable.
chmod 644 /opt/zkteco/secrets/fcm-service-account.json

echo "=== 5. HTTP nginx (ACME + proxy) ==="
rm -f /etc/nginx/sites-enabled/default
cp /root/nginx-sboxpos.com.http-bootstrap.conf /etc/nginx/sites-available/sboxpos.com
ln -sfn /etc/nginx/sites-available/sboxpos.com /etc/nginx/sites-enabled/sboxpos.com
nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo "=== 6. Let's Encrypt ==="
if [ ! -f /etc/letsencrypt/live/sboxpos.com/fullchain.pem ]; then
  certbot certonly --webroot -w /var/www/html \
    -d sboxpos.com -d www.sboxpos.com \
    --agree-tos --non-interactive \
    -m sanapos.vn@gmail.com \
    --keep-until-expiring
fi

if [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
  if [ -f /root/options-ssl-nginx.conf ]; then
    cp /root/options-ssl-nginx.conf /etc/letsencrypt/options-ssl-nginx.conf
  else
    cat > /etc/letsencrypt/options-ssl-nginx.conf <<'SSLEOF'
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_session_tickets off;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
SSLEOF
  fi
fi
if [ ! -f /etc/letsencrypt/ssl-dhparams.pem ]; then
  openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
fi

if [ -f /etc/letsencrypt/live/sboxpos.com/fullchain.pem ] && [ -f /root/nginx-sboxpos.com.conf ]; then
  cp /root/nginx-sboxpos.com.conf /etc/nginx/sites-available/sboxpos.com
  nginx -t && systemctl reload nginx
  echo "SSL vhost enabled"
else
  echo "SSL cert not ready — staying on HTTP bootstrap"
fi

# Renew twice daily via systemd timer (certbot package installs it)
systemctl enable --now certbot.timer 2>/dev/null || true

echo "=== BOOTSTRAP HOST DONE ==="
docker --version
nginx -v 2>&1
ls -la /etc/letsencrypt/live/sboxpos.com 2>/dev/null || echo "no cert yet"
