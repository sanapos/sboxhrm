#!/bin/bash
set -euo pipefail
cd /root

API_URL="${API_BASE_URL:-https://sboxpos.com}"

echo "=== 1. Extract API source ==="
rm -rf api_src
mkdir api_src
tar -xzf api_src.tar.gz -C api_src

echo "=== 2. Build API docker image ==="
cd api_src
docker build --no-cache -t zktecoadms-api:latest -f ZKTecoADMS.Api/Dockerfile .
cd /opt/zkteco

echo "=== 3. Start / recreate stack ==="
# First install uses docker-compose.sboxpos.yml copied as docker-compose.prod.yml
if [ ! -f docker-compose.prod.yml ] && [ -f docker-compose.sboxpos.yml ]; then
  cp docker-compose.sboxpos.yml docker-compose.prod.yml
fi
docker compose -f docker-compose.prod.yml up -d
sleep 8
docker compose -f docker-compose.prod.yml up -d --force-recreate zktecoadms-api
sleep 8
docker ps --format "{{.Names}} {{.Status}}"

echo "=== 4. Wait for API ==="
for i in $(seq 1 40); do
  if curl -sf http://127.0.0.1:7070/health >/dev/null 2>&1; then
    echo "API healthy after ${i}0s-ish"
    break
  fi
  echo "waiting API... $i"
  sleep 3
done
curl -sS -o /dev/null -w "local health %{http_code}\n" http://127.0.0.1:7070/health || true

echo "=== 5. Deploy Flutter web ==="
cd /root
rm -rf web
tar -xzf flutter_web.tar.gz
docker exec zkteco_flutter rm -rf /usr/share/nginx/html/ || true
docker exec zkteco_flutter mkdir -p /usr/share/nginx/html
docker cp web/. zkteco_flutter:/usr/share/nginx/html/
docker exec zkteco_flutter rm -f /usr/share/nginx/html/flutter_service_worker.js 2>/dev/null || true
if [ -f /root/flutter_nginx.conf ]; then
  docker cp /root/flutter_nginx.conf zkteco_flutter:/etc/nginx/conf.d/default.conf
fi
docker exec zkteco_flutter nginx -s reload 2>/dev/null || docker exec zkteco_flutter nginx -t || true

echo "=== 5b. Inject API_BASE_URL ($API_URL) ==="
docker exec zkteco_flutter sh -c "
  for f in /usr/share/nginx/html/index.html /usr/share/nginx/html/config.js /usr/share/nginx/html/home.html; do
    [ -f \"\$f\" ] || continue
    sed -i \"s|__API_BASE_URL__|${API_URL}|g\" \"\$f\"
    sed -i \"s|https://sbox.sana.vn|${API_URL}|g\" \"\$f\"
    sed -i \"s|https://sboxhrm.com|${API_URL}|g\" \"\$f\"
  done
  grep -E 'API_BASE_URL|SITE_URL' /usr/share/nginx/html/config.js 2>/dev/null | head -6
"
echo "Web files: $(docker exec zkteco_flutter sh -c 'ls /usr/share/nginx/html | wc -l')"

echo "=== 6. Verify ==="
sleep 2
curl -sS -o /dev/null -w "http health %{http_code}\n" http://127.0.0.1:7070/health || true
curl -sk -o /dev/null -w "https health %{http_code}\n" https://sboxpos.com/health || true
curl -sk -o /dev/null -w "https web %{http_code}\n" https://sboxpos.com/ || true
curl -sk https://sboxpos.com/config.js 2>/dev/null | grep -E 'API_BASE_URL|SITE_URL' || true

echo "=== DONE sboxpos deploy ==="
