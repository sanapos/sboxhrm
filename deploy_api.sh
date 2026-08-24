#!/bin/bash
set -euo pipefail
cd /root
rm -rf api_src
mkdir api_src
tar -xzf api_src.tar.gz -C api_src
cd api_src
docker build -t zktecoadms-api:latest -f ZKTecoADMS.Api/Dockerfile . 2>&1 | tail -5
cd /opt/zkteco
docker compose -f docker-compose.prod.yml up -d --force-recreate zktecoadms-api
echo "DEPLOY DONE"
