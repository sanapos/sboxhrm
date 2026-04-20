#!/bin/bash
TOKEN=$(curl -s http://localhost:7070/api/auth/login -X POST -H 'Content-Type: application/json' -d '{"storeCode":"demo","userName":"demo@gmail.com","password":"123456"}' | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('data',{}).get('token','') if isinstance(d.get('data'),dict) else ''; print(t)" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  TOKEN=$(curl -s http://localhost:7070/api/auth/login -X POST -H 'Content-Type: application/json' -d '{"storeCode":"demo","userName":"demo@gmail.com","password":"Demo@123"}' | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('data',{}).get('token','') if isinstance(d.get('data'),dict) else ''; print(t)" 2>/dev/null)
fi
if [ -z "$TOKEN" ]; then
  TOKEN=$(curl -s http://localhost:7070/api/auth/login -X POST -H 'Content-Type: application/json' -d '{"storeCode":"demo","userName":"demo@gmail.com","password":"Abcd@1234"}' | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('data',{}).get('token','') if isinstance(d.get('data'),dict) else ''; print(t)" 2>/dev/null)
fi
echo "TOKEN_LEN=${#TOKEN}"
if [ ${#TOKEN} -gt 20 ]; then
  echo "--- inventories response ---"
  curl -s -w '\nHTTP_CODE:%{http_code}' "http://localhost:7070/api/Assets/inventories" -H "Authorization: Bearer $TOKEN"
  echo ""
fi
echo "--- docker logs ---"  
docker logs --tail 10 zkteco_api 2>&1 | grep INV