#!/bin/bash
set -euo pipefail
# SMTP_* and FCM file must already be in place.
# Do not echo secrets.

if [ ! -s /opt/zkteco/secrets/fcm-service-account.json ]; then
  echo "MISSING FCM json"
  exit 1
fi
chmod 644 /opt/zkteco/secrets/fcm-service-account.json
python3 - <<'PY'
import json
from pathlib import Path
p = Path('/opt/zkteco/secrets/fcm-service-account.json')
data = json.loads(p.read_text())
assert data.get('type') == 'service_account', data.get('type')
assert data.get('project_id') == 'sbox-hrm', data.get('project_id')
print('fcm_ok project=', data.get('project_id'), 'client=', data.get('client_email'))
PY

python3 - <<'PY'
from pathlib import Path
p = Path('/opt/zkteco/.env')
text = p.read_text(encoding='utf-8') if p.exists() else ''
vals = {
  'SMTP_HOST': 'smtp.gmail.com',
  'SMTP_PORT': '587',
  'SMTP_USERNAME': 'phanmemquanlynhansusbox@gmail.com',
  'SMTP_FROM_EMAIL': 'phanmemquanlynhansusbox@gmail.com',
  'SMTP_FROM_NAME': 'SBOX',
  'SMTP_ENABLE_SSL': 'true',
}
# password injected from env APPLY_SMTP_PASSWORD
import os
pw = os.environ.get('APPLY_SMTP_PASSWORD', '')
if not pw:
    raise SystemExit('APPLY_SMTP_PASSWORD missing')
vals['SMTP_PASSWORD'] = pw
lines = text.splitlines()
out = []
seen = set()
for line in lines:
    if not line.strip() or line.lstrip().startswith('#') or '=' not in line:
        out.append(line)
        continue
    k = line.split('=', 1)[0].strip()
    if k in vals:
        out.append(f'{k}={vals[k]}')
        seen.add(k)
    else:
        out.append(line)
for k, v in vals.items():
    if k not in seen:
        out.append(f'{k}={v}')
p.write_text('\n'.join(out) + '\n', encoding='utf-8')
print('env_smtp_updated', 'user=' + vals['SMTP_USERNAME'])
PY

# Token table for FCM (idempotent)
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -v ON_ERROR_STOP=0 <<'SQL'
CREATE TABLE IF NOT EXISTS "UserDeviceTokens" (
    "Id" uuid PRIMARY KEY,
    "UserId" uuid NOT NULL,
    "Token" varchar(512) NOT NULL,
    "Platform" varchar(16) NOT NULL DEFAULT '',
    "DeviceName" varchar(128),
    "AppVersion" varchar(32),
    "IsDisabled" boolean NOT NULL DEFAULT false,
    "LastUsedAt" timestamp without time zone,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text,
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text
);
CREATE UNIQUE INDEX IF NOT EXISTS "UX_UserDeviceTokens_Token" ON "UserDeviceTokens" ("Token");
CREATE INDEX IF NOT EXISTS "IX_UserDeviceTokens_UserId" ON "UserDeviceTokens" ("UserId");
CREATE INDEX IF NOT EXISTS "IX_UserDeviceTokens_User_Disabled" ON "UserDeviceTokens" ("UserId", "IsDisabled");
SQL

cd /opt/zkteco
docker compose -f docker-compose.prod.yml up -d --force-recreate zktecoadms-api
echo API_RECREATED
sleep 20
docker ps --filter name=zkteco_api --format '{{.Names}} {{.Status}}'
echo '--- firebase/smtp logs ---'
docker logs zkteco_api 2>&1 | grep -E 'Firebase|Email sent|Failed to send email|Firebase credential|SMTP' | tail -20
curl -sS -o /dev/null -w 'health %{http_code}\n' http://127.0.0.1:7070/health || true
