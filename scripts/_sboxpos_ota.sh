#!/bin/bash
set -euo pipefail
CID=$(docker ps -qf name=zkteco_api | head -1)
if [ -z "$CID" ]; then CID=$(docker ps -qf name=zktecoadms-api | head -1); fi
echo "Using container $CID"
docker exec -u 0 "$CID" mkdir -p /app/wwwroot/downloads
docker exec -u 0 -i "$CID" sh -c 'cat > /app/wwwroot/downloads/sbox-pos.apk' < /root/sbox-pos-release/sbox-pos.apk
docker exec -u 0 -i "$CID" sh -c 'cat > /app/wwwroot/downloads/sbox-pos-release.json' < /root/sbox-pos-release/sbox-pos-release.json
docker exec -u 0 "$CID" ls -la /app/wwwroot/downloads/sbox-pos.apk /app/wwwroot/downloads/sbox-pos-release.json
echo "=== release json ==="
curl -sS http://127.0.0.1:7070/api/app/pos-android-release
echo
curl -sS -o /dev/null -w "apk:%{http_code} size:%{size_download}\n" http://127.0.0.1:7070/api/app/pos-android-apk
echo POS_OTA_DONE
