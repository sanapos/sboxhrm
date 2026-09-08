#!/bin/bash
set -euo pipefail
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c 'SELECT COUNT(*) AS users FROM "AspNetUsers";'
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c 'SELECT "UserName", "Email", "Role" FROM "AspNetUsers" LIMIT 10;'
echo "--- endpoints ---"
curl -sk -o /dev/null -w "www_redir %{http_code} %{redirect_url}\n" https://www.sboxpos.com/ || true
curl -sk -o /dev/null -w "publicsettings %{http_code}\n" https://sboxpos.com/api/publicsettings || true
curl -sk -o /dev/null -w "maintenance %{http_code}\n" https://sboxpos.com/api/maintenance/active || true
curl -sk -o /dev/null -w "health %{http_code}\n" https://sboxpos.com/health || true
echo DONE_VERIFY
