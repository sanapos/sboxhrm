#!/bin/bash
cd /root
rm -rf web_build3
unzip -q -o web_build3.zip -d web_build3
for f in main.dart.js main.dart.js_1.part.js flutter.js flutter_bootstrap.js flutter_service_worker.js manifest.json favicon.png version.json index.html; do
    [ -f "web_build3/$f" ] && docker cp "web_build3/$f" "zkteco_api:/app/wwwroot/$f" && echo "OK: $f"
done
docker cp "web_build3/assets/." "zkteco_api:/app/wwwroot/assets/" && echo "OK: assets/"
echo "Done deploying v3"