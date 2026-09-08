#!/bin/bash
set -u
docker ps --filter name=zkteco_api --format '{{.Names}} {{.Status}}'
echo '--- container env (redacted) ---'
docker exec zkteco_api printenv | grep -E 'Email__|Fcm__' | sed -E 's/(Password|Secret)=.*/\1=***/'
echo '--- fcm mount ---'
docker exec zkteco_api sh -c 'ls -la /app/secrets/fcm-service-account.json; wc -c /app/secrets/fcm-service-account.json'
echo '--- api logs ---'
docker logs zkteco_api 2>&1 | grep -E 'Firebase|credential|push notifications' | tail -20
echo '--- tokens table ---'
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c 'SELECT to_regclass('"'"'public."UserDeviceTokens"'"'"') AS tokens;'
curl -sS -o /dev/null -w 'health %{http_code}\n' http://127.0.0.1:7070/health
# SMTP auth test without sending mail
python3 - <<'PY'
import os, smtplib, ssl
from pathlib import Path
vals = {}
for line in Path('/opt/zkteco/.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v = line.split('=',1)
        vals[k.strip()] = v.strip()
user = vals.get('SMTP_USERNAME','')
pw = vals.get('SMTP_PASSWORD','')
host = vals.get('SMTP_HOST','smtp.gmail.com')
port = int(vals.get('SMTP_PORT','587'))
print('smtp_try', host, port, 'user=', user)
try:
    with smtplib.SMTP(host, port, timeout=20) as s:
        s.ehlo()
        s.starttls(context=ssl.create_default_context())
        s.ehlo()
        s.login(user, pw)
    print('smtp_auth_ok')
except Exception as e:
    print('smtp_auth_fail', type(e).__name__, str(e)[:200])
PY
echo DONE_SMTP_FCM
