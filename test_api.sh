#!/bin/bash
# Login
RESP=$(curl -s -X POST http://127.0.0.1:7070/api/auth/admin-login -H "Content-Type: application/json" -d '{"userName":"sanapos.vn@gmail.com","password":"Ti100600@"}')
TOKEN=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['accessToken'])")
echo "TOKEN_LEN: ${#TOKEN}"

echo "--- notifications/summary ---"
curl -s -w '\nHTTP:%{http_code}\n' "http://127.0.0.1:7070/api/notifications/summary" -H "Authorization: Bearer $TOKEN"

echo "--- POST settings/app ---"
curl -s -w '\nHTTP:%{http_code}\n' -X POST "http://127.0.0.1:7070/api/settings/app" -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d '{"key":"__test__","value":"ok","group":"system","dataType":"string"}'