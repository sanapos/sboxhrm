#!/bin/bash
set -euo pipefail
ENV_FILE=/opt/zkteco/.env
if [ -f "$ENV_FILE" ]; then
  echo ".env already exists, skip"
  exit 0
fi
JWTA=$(openssl rand -base64 48 | tr -d '\n')
JWTR=$(openssl rand -base64 48 | tr -d '\n')
PGPW=$(openssl rand -base64 24 | tr -d '\n=')
RDPW=$(openssl rand -hex 16)
cat > "$ENV_FILE" <<EOF
SERVER_HOST=sboxpos.com
API_PORT=7070
FLUTTER_PORT=3000
API_BASE_URL=https://sboxpos.com
PUBLIC_WEB_BASE_URL=https://sboxpos.com
POSTGRES_DB=ZKTecoADMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${PGPW}
REDIS_PASSWORD=${RDPW}
JWT_ACCESS_SECRET=${JWTA}
JWT_REFRESH_SECRET=${JWTR}
JWT_ISSUER=https://sboxpos.com
JWT_AUDIENCE=https://sboxpos.com
JWT_ACCESS_EXPIRATION=1500
JWT_REFRESH_EXPIRATION=120
DEFAULT_EMPLOYEE_PASSWORD=Ti100600@
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=
SMTP_FROM_NAME=SBOX POS
SMTP_ENABLE_SSL=true
EOF
chmod 600 "$ENV_FILE"
echo "Wrote $ENV_FILE"
