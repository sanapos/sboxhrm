#!/bin/bash
set -e
cd /root
rm -rf web
tar -xzf flutter_web.tar.gz
docker exec zkteco_flutter rm -rf /usr/share/nginx/html/
docker cp web/. zkteco_flutter:/usr/share/nginx/html/
docker exec zkteco_flutter sh -c "for f in /usr/share/nginx/html/index.html /usr/share/nginx/html/config.js; do [ -f \"\$f\" ] && sed -i 's|__API_BASE_URL__|https://sboxhrm.com|g' \"\$f\"; done"
echo WEB_OK
