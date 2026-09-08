#!/bin/bash
set -u
sleep 12
echo '--- health ---'
curl -sS -o /dev/null -w 'health %{http_code}\n' http://127.0.0.1:7070/health || true
echo '--- last 80 lines ---'
docker logs --since 90s zkteco_api 2>&1 | tail -80
echo '--- json check ---'
python3 - <<'PY'
import json
from pathlib import Path
p=Path('/opt/zkteco/secrets/fcm-service-account.json')
raw=p.read_bytes()
print('bytes', len(raw), 'bom', raw[:3])
d=json.loads(raw.decode('utf-8-sig'))
print('keys', sorted(d.keys()))
print('type', d.get('type'), 'project', d.get('project_id'))
print('pk_starts', (d.get('private_key') or '')[:30].replace('\n','\\n'))
PY
