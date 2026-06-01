#!/bin/bash
WEB=/root/web_build_new
echo "Deploying web build..."

for f in main.dart.js main.dart.js_1.part.js flutter.js flutter_bootstrap.js flutter_service_worker.js manifest.json favicon.png version.json; do
    [ -f "$WEB/$f" ] && docker cp "$WEB/$f" "zkteco_api:/app/wwwroot/$f" && echo "OK: $f"
done

docker cp "$WEB/assets/." "zkteco_api:/app/wwwroot/assets/" && echo "OK: assets/"
docker cp "$WEB/icons/." "zkteco_api:/app/wwwroot/icons/" 2>/dev/null && echo "OK: icons/" || true
echo "=== Font check ==="
docker exec zkteco_api find /app/wwwroot/assets/assets/fonts -name "*.ttf" -exec wc -c {} \;
echo "Deploy complete"