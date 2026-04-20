#!/bin/bash
TOKEN=$(curl -s http://localhost:7070/api/auth/login -X POST -H 'Content-Type: application/json' -d '{"storeCode":"S001","userName":"admin","password":"Admin@123"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('token','NO_TOKEN'))" 2>/dev/null)
echo "TOKEN: ${TOKEN:0:50}..."
curl -s "http://localhost:7070/api/Assets/inventories" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' 2>&1 | head -c 2000
