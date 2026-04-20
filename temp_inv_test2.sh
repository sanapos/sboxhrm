#!/bin/bash
TOKEN=$(curl -s http://localhost:7070/api/auth/login -X POST -H 'Content-Type: application/json' -d '{"storeCode":"demo","userName":"demo@gmail.com","password":"Admin@123"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('token','') if d.get('data') else '')")
echo "TOKEN_LEN=${#TOKEN}"
echo "--- RAW RESPONSE ---"
curl -s -w '\nHTTP_CODE:%{http_code}' "http://localhost:7070/api/Assets/inventories" -H "Authorization: Bearer $TOKEN"
echo ""
echo "--- END ---"