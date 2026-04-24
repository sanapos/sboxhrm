#!/bin/bash
set -e
cd /root

echo "=== 1. Extract API source ==="
rm -rf api_src
mkdir api_src
tar -xzf api_src.tar.gz -C api_src

echo "=== 2. Build API docker image ==="
cd api_src
docker build -t zktecoadms-api:latest -f ZKTecoADMS.Api/Dockerfile . 2>&1 | tail -20

echo "=== 3. Recreate API container ==="
cd /opt/zkteco
docker compose -f docker-compose.prod.yml up -d --force-recreate zktecoadms-api 2>&1 | tail -10
sleep 5
docker ps --filter name=zkteco_api --format "{{.Names}} {{.Status}}"

echo "=== 4. Run SQL migrations ==="
for f in add_system_announcements.sql add_maintenance_windows.sql add_marketing_p3.sql; do
  echo "--- $f ---"
  docker cp /root/$f zkteco_postgres:/tmp/$f
  docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/$f 2>&1 | tail -10
done

echo "=== 5. Deploy Flutter web ==="
cd /root
rm -rf web
tar -xzf flutter_web.tar.gz
docker exec zkteco_flutter rm -rf /usr/share/nginx/html/
docker cp web/. zkteco_flutter:/usr/share/nginx/html/
echo "Web file count: $(docker exec zkteco_flutter sh -c 'ls /usr/share/nginx/html/ | wc -l')"

echo "=== 6. Verify endpoints ==="
sleep 3
echo "[Public maintenance]"
curl -sk https://sbox.sana.vn/api/maintenance/active | head -c 400
echo ""
echo "[API health]"
curl -sk -o /dev/null -w "HTTP %{http_code}\n" https://sbox.sana.vn/health || true

echo "=== DONE ==="
