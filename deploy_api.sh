#!/bin/bash
set -euo pipefail
cd /root
rm -rf api_src
mkdir api_src
tar -xzf api_src.tar.gz -C api_src
# Keep the running image as a rollback before building the new one.
if docker image inspect zktecoadms-api:latest >/dev/null 2>&1; then
  docker tag zktecoadms-api:latest "zktecoadms-api:rollback-$(date +%Y%m%d-%H%M%S)"
fi
cd api_src
docker build -t zktecoadms-api:latest -f ZKTecoADMS.Api/Dockerfile . 2>&1 | tail -5
cd /opt/zkteco
docker compose -f docker-compose.prod.yml up -d --force-recreate zktecoadms-api
echo "DEPLOY DONE"
# Disk housekeeping (never fails the deploy): keep the 3 newest rollback tags,
# drop dangling images and build cache older than 48h.
{
  docker images zktecoadms-api --format "{{.Tag}}" | grep "^rollback-" | sort -r | tail -n +4 \
    | while read -r t; do docker rmi "zktecoadms-api:$t" >/dev/null 2>&1 && echo "Removed old rollback: $t"; done
  docker image prune -f >/dev/null 2>&1
  docker builder prune -f --filter until=48h >/dev/null 2>&1
  df -h / | tail -1
} || true
