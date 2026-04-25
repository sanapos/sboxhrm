#!/bin/bash
set -e
cd /root
tar -xzf dlls_patch.tar.gz
docker cp publish_out/ZKTecoADMS.Api.dll zkteco_api:/app/
docker cp publish_out/ZKTecoADMS.Application.dll zkteco_api:/app/
docker cp publish_out/ZKTecoADMS.Domain.dll zkteco_api:/app/
docker cp publish_out/ZKTecoADMS.Infrastructure.dll zkteco_api:/app/
docker restart zkteco_api
sleep 5
docker ps --filter name=zkteco_api --format "{{.Names}} {{.Status}}"
echo "PATCH_DONE"
