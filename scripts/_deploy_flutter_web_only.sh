#!/bin/bash
set -euo pipefail
cd /root

API_URL="${API_BASE_URL:?API_BASE_URL required}"

echo "=== Deploy Flutter web (API_BASE_URL=$API_URL) ==="
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

if [ -f web/flutter_bootstrap.js ]; then
  sed -i 's/serviceWorkerSettings: {[^}]*}//g' web/flutter_bootstrap.js 2>/dev/null || true
  sed -i 's/_flutter.loader.load({[[:space:]]*});/_flutter.loader.load();/g' web/flutter_bootstrap.js 2>/dev/null || true
  docker cp web/flutter_bootstrap.js zkteco_flutter:/usr/share/nginx/html/flutter_bootstrap.js
fi

docker exec zkteco_flutter sh -c "
  for f in /usr/share/nginx/html/index.html /usr/share/nginx/html/config.js /usr/share/nginx/html/home.html; do
    [ -f \"\$f\" ] || continue
    sed -i \"s|__API_BASE_URL__|${API_URL}|g\" \"\$f\"
    sed -i \"s|https://sbox.sana.vn|${API_URL}|g\" \"\$f\"
    if [ \"${API_URL}\" = \"https://sboxpos.com\" ]; then
      sed -i \"s|https://sboxhrm.com|${API_URL}|g\" \"\$f\"
    fi
  done
  grep -E 'API_BASE_URL|SITE_URL' /usr/share/nginx/html/config.js 2>/dev/null | head -6 || true
"

echo "Web files: $(docker exec zkteco_flutter sh -c 'ls /usr/share/nginx/html | wc -l')"
echo "DONE flutter-only deploy $API_URL"
