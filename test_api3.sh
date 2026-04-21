#!/bin/bash
echo 'eyJ1c2VyTmFtZSI6InNhbmFwb3Mudm5AZ21haWwuY29tIiwicGFzc3dvcmQiOiJUaTEwMDYwMEAifQ==' | base64 -d | curl -s -X POST http://127.0.0.1:7070/api/auth/admin-login -H 'Content-Type: application/json' -d @- | jq -r '.data.accessToken' > /tmp/sa_token.txt
TOKEN=$(cat /tmp/sa_token.txt)
echo "TOKEN_LEN: ${#TOKEN}"
echo "=== /api/notifications/summary ==="
curl -s -w '\nHTTP_CODE:%{http_code}' http://127.0.0.1:7070/api/notifications/summary -H "Authorization: Bearer $TOKEN"
echo ""
echo "=== POST /api/settings/app ==="
echo '{"key":"GoogleDriveEnabled","value":"true","group":"system","dataType":"string"}' | curl -s -w '\nHTTP_CODE:%{http_code}' -X POST http://127.0.0.1:7070/api/settings/app -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d @-
echo ""
echo "=== GET /api/system-admin/settings ==="
curl -s http://127.0.0.1:7070/api/system-admin/settings -H "Authorization: Bearer $TOKEN" | jq '.isSuccess'