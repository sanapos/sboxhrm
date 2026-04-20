#!/bin/bash
set -e
echo "=== Replacing source files ==="
rm -rf /opt/zkteco/src/ZKTecoADMS.Api /opt/zkteco/src/ZKTecoADMS.Application /opt/zkteco/src/ZKTecoADMS.Domain /opt/zkteco/src/ZKTecoADMS.Infrastructure
cp -r /opt/zkteco/src_new/* /opt/zkteco/src/
echo "=== Source files: ==="
ls /opt/zkteco/src/
echo "=== Building Docker image ==="
cd /opt/zkteco/src
docker build --no-cache -t zktecoadms-api:latest -f ZKTecoADMS.Api/Dockerfile .
echo "=== Build done, restarting ==="
cd /opt/zkteco
docker-compose -f docker-compose.prod.yml up -d
echo "=== DONE ==="
