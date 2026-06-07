#!/bin/bash
set -e
cd /root

echo "=== 1. Extract API source ==="
rm -rf api_src
mkdir api_src
tar -xzf api_src.tar.gz -C api_src

echo "=== 2. Build API docker image ==="
cd api_src
docker build --no-cache -t zktecoadms-api:latest -f ZKTecoADMS.Api/Dockerfile . 2>&1 | tail -25

echo "=== 3. Recreate API container ==="
cd /opt/zkteco
docker compose -f docker-compose.prod.yml up -d --force-recreate zktecoadms-api 2>&1 | tail -10
sleep 5
docker ps --filter name=zkteco_api --format "{{.Names}} {{.Status}}"

echo "=== 4. Run SQL migrations ==="
# Apply all pending EF migrations
if [ -f /root/apply_all_migrations.sql ]; then
  echo "--- apply_all_migrations.sql ---"
  docker cp /root/apply_all_migrations.sql zkteco_postgres:/tmp/apply_all_migrations.sql
  docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/apply_all_migrations.sql 2>&1 | tail -20
fi
if [ -f /root/apply_site_photo_ef_migration.sql ]; then
  echo "--- apply_site_photo_ef_migration.sql ---"
  docker cp /root/apply_site_photo_ef_migration.sql zkteco_postgres:/tmp/apply_site_photo_ef_migration.sql
  docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/apply_site_photo_ef_migration.sql 2>&1 | tail -5
fi
if [ -f /root/apply_mobile_location_employees.sql ]; then
  echo "--- apply_mobile_location_employees.sql ---"
  docker cp /root/apply_mobile_location_employees.sql zkteco_postgres:/tmp/apply_mobile_location_employees.sql
  docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/apply_mobile_location_employees.sql 2>&1 | tail -10
fi
# Legacy SQL scripts (kept for compatibility)
if [ -f /root/fix_employee_unique_indexes.sql ]; then
  docker cp /root/fix_employee_unique_indexes.sql zkteco_postgres:/tmp/fix_employee_unique_indexes.sql
  docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/fix_employee_unique_indexes.sql 2>&1 | tail -5
fi
if [ -f /root/ensure_employee_live_locations.sql ]; then
  docker cp /root/ensure_employee_live_locations.sql zkteco_postgres:/tmp/ensure_employee_live_locations.sql
  docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/ensure_employee_live_locations.sql 2>&1 | tail -3
fi
for f in add_system_announcements.sql add_maintenance_windows.sql add_marketing_p3.sql; do
  if [ -f /root/$f ]; then
    echo "--- $f ---"
    docker cp /root/$f zkteco_postgres:/tmp/$f
    docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/$f 2>&1 | tail -10
  fi
done

echo "=== 5. Deploy Flutter web ==="
cd /root
rm -rf web
tar -xzf flutter_web.tar.gz
docker exec zkteco_flutter rm -rf /usr/share/nginx/html/
docker cp web/. zkteco_flutter:/usr/share/nginx/html/
docker exec zkteco_flutter rm -f /usr/share/nginx/html/flutter_service_worker.js 2>/dev/null || true
if [ -f /root/flutter_nginx.conf ]; then
  docker cp /root/flutter_nginx.conf zkteco_flutter:/etc/nginx/conf.d/default.conf
  docker exec zkteco_flutter nginx -s reload 2>/dev/null || docker exec zkteco_flutter nginx -t
fi
if [ -f web/flutter_bootstrap.js ]; then
  sed -i 's/serviceWorkerSettings: {[^}]*}//g' web/flutter_bootstrap.js 2>/dev/null || true
  sed -i 's/_flutter.loader.load({[[:space:]]*});/_flutter.loader.load();/g' web/flutter_bootstrap.js 2>/dev/null || true
  docker cp web/flutter_bootstrap.js zkteco_flutter:/usr/share/nginx/html/flutter_bootstrap.js
fi

API_URL="${API_BASE_URL:-https://sbox.sana.vn}"
echo "=== 5b. Inject API_BASE_URL into static web ($API_URL) ==="
docker exec zkteco_flutter sh -c "
  for f in /usr/share/nginx/html/index.html /usr/share/nginx/html/config.js; do
    [ -f \"\$f\" ] || continue
    sed -i \"s|__API_BASE_URL__|${API_URL}|g\" \"\$f\"
  done
  grep -E 'API_BASE_URL|api-base-url' /usr/share/nginx/html/config.js /usr/share/nginx/html/index.html 2>/dev/null | head -4
"
echo "Web file count: $(docker exec zkteco_flutter sh -c 'ls /usr/share/nginx/html/ | wc -l')"

echo "=== 6. Verify endpoints ==="
sleep 3
echo "[Public maintenance]"
curl -sk https://sbox.sana.vn/api/maintenance/active | head -c 400
echo ""
echo "[API health]"
curl -sk -o /dev/null -w "HTTP %{http_code}\n" https://sbox.sana.vn/health || true
echo "[Web config.js API_BASE_URL]"
curl -sk https://sbox.sana.vn/config.js | grep API_BASE_URL || true

echo "=== DONE ==="
