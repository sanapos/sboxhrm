#!/bin/bash
echo "=== Deploying web build v2 ==="
cd /root
unzip -q -o web_build2.zip -d web_build2

for f in main.dart.js main.dart.js_1.part.js flutter.js flutter_bootstrap.js flutter_service_worker.js manifest.json favicon.png version.json index.html; do
    [ -f "web_build2/$f" ] && docker cp "web_build2/$f" "zkteco_api:/app/wwwroot/$f" && echo "OK: $f"
done

docker cp "web_build2/assets/." "zkteco_api:/app/wwwroot/assets/" && echo "OK: assets/"
echo "=== Done ==="
echo "Font check:"
docker exec zkteco_api find /app/wwwroot/assets/assets/fonts -name "*.ttf" -exec wc -c {} \;