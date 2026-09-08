#!/bin/bash
set -euo pipefail
mkdir -p /opt/zkteco/gc
chmod 755 /opt/zkteco/gc

python3 - <<'PY'
from pathlib import Path
p = Path("/opt/zkteco/docker-compose.prod.yml")
t = p.read_text()
changed = False
if "Kestrel__Limits__MaxRequestBodySize" not in t:
    out = []
    inserted = False
    for line in t.splitlines(True):
        out.append(line)
        if (not inserted) and "PublicWebBaseUrl=" in line:
            indent = line[:len(line) - len(line.lstrip())]
            out.append(f"{indent}- Kestrel__Limits__MaxRequestBodySize=314572800\n")
            inserted = True
            changed = True
    t = "".join(out)
if "/opt/zkteco/gc:/app/gc" not in t:
    out = []
    inserted = False
    for line in t.splitlines(True):
        out.append(line)
        if (not inserted) and "fcm-service-account.json" in line:
            indent = line[:len(line) - len(line.lstrip())]
            out.append(f"{indent}- /opt/zkteco/gc:/app/gc\n")
            inserted = True
            changed = True
    t = "".join(out)
if changed:
    p.write_text(t)
    print("compose patched")
else:
    print("compose already ok")
PY

python3 - <<'PY'
from pathlib import Path
cands = list(Path("/etc/nginx/sites-enabled").glob("*")) + list(Path("/etc/nginx/conf.d").glob("*"))
for p in cands:
    if not p.is_file():
        continue
    t = p.read_text(errors="ignore")
    if "sbox.sana.vn" not in t or "client_max_body_size" not in t:
        continue
    orig = t
    t = t.replace("client_max_body_size 150M;", "client_max_body_size 300M;")
    t = t.replace("client_max_body_size 50M;", "client_max_body_size 300M;")
    if "location /api/" in t and "proxy_read_timeout 600s" not in t:
        t = t.replace(
            "location /api/ {",
            "location /api/ {\n        client_max_body_size 300M;\n        proxy_read_timeout 600s;\n        proxy_send_timeout 600s;\n        client_body_timeout 600s;",
        )
    if t != orig:
        p.write_text(t)
        print(f"nginx patched {p}")
    else:
        print(f"nginx already ok {p}")
PY

nginx -t
systemctl reload nginx
echo "HOST_PATCH_DONE"
