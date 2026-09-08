#!/bin/bash
set -euo pipefail
NEW_REDIS=$(openssl rand -hex 16)
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${NEW_REDIS}|" /opt/zkteco/.env
echo "redis password rotated"

docker cp /root/add_pos_print_cloud.sql zkteco_postgres:/tmp/add_pos_print_cloud.sql
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT to_regclass('public.Stores') AS stores, to_regclass('public.PosStorePrinters') AS printers;"
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/add_pos_print_cloud.sql
if [ -f /root/apply_all_migrations.sql ]; then
  docker cp /root/apply_all_migrations.sql zkteco_postgres:/tmp/apply_all_migrations.sql
  docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -v ON_ERROR_STOP=0 -f /tmp/apply_all_migrations.sql | tail -25
fi
cd /opt/zkteco
docker compose -f docker-compose.prod.yml up -d --force-recreate redis zktecoadms-api
echo RECREATED
sleep 8
docker ps --format '{{.Names}} {{.Status}}'
