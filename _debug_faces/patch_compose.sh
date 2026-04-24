#!/bin/bash
set -e
cd /opt/zkteco
cp docker-compose.prod.yml docker-compose.prod.yml.bak
if ! grep -q FACE_SIDECAR_URL docker-compose.prod.yml; then
  python3 - <<'PY'
import re
with open('/opt/zkteco/docker-compose.prod.yml') as f: s=f.read()
needle='- DatabaseTools__PgRestorePath=pg_restore'
repl='- DatabaseTools__PgRestorePath=pg_restore\n      - FACE_SIDECAR_URL=http://face_sidecar:8000'
if needle not in s: raise SystemExit('needle not found')
s=s.replace(needle,repl,1)
# append face_sidecar service before 'volumes:' line at bottom
block='''
  # Python insightface sidecar: SCRFD detection + 5pt alignment + ArcFace R50
  face_sidecar:
    build:
      context: ./face_service
      dockerfile: Dockerfile
    image: face-sidecar:latest
    container_name: face_sidecar
    restart: unless-stopped
    volumes:
      - /opt/zkteco/ZKTecoADMS.Api/wwwroot/models:/models/models/buffalo_l:ro
    networks:
      - zkteconet
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 3G

'''
# insert before top-level 'volumes:' key
m=re.search(r'^volumes:', s, re.M)
if not m: raise SystemExit('volumes block not found')
s=s[:m.start()]+block+s[m.start():]
with open('/opt/zkteco/docker-compose.prod.yml','w') as f: f.write(s)
print('patched')
PY
fi
grep -n FACE_SIDECAR\|face_sidecar /opt/zkteco/docker-compose.prod.yml
