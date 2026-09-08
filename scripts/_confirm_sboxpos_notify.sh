#!/bin/bash
set -u
START=$(docker inspect -f '{{.State.StartedAt}}' zkteco_api)
echo "api_started $START"
echo '--- firebase since start ---'
docker logs --since "$START" zkteco_api 2>&1 | grep -E 'Firebase|push notifications' || echo '(no Firebase error since start — Production log level hides success info)'
echo '--- smtp send self-test ---'
python3 - <<'PY'
import smtplib, ssl
from email.mime.text import MIMEText
from pathlib import Path
vals = {}
for line in Path('/opt/zkteco/.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v = line.split('=',1)
        vals[k.strip()] = v.strip()
user = vals['SMTP_USERNAME']
pw = vals['SMTP_PASSWORD']
msg = MIMEText('SBOX POS SMTP test from sboxpos.com — reset mật khẩu / OTP đã cấu hình.', 'plain', 'utf-8')
msg['Subject'] = 'SBOX POS: SMTP đã hoạt động'
msg['From'] = user
msg['To'] = user
try:
    with smtplib.SMTP(vals.get('SMTP_HOST','smtp.gmail.com'), int(vals.get('SMTP_PORT','587')), timeout=25) as s:
        s.ehlo()
        s.starttls(context=ssl.create_default_context())
        s.login(user, pw)
        s.sendmail(user, [user], msg.as_string())
    print('smtp_send_ok to', user)
except Exception as e:
    print('smtp_send_fail', type(e).__name__, str(e)[:240])
PY
echo DONE
