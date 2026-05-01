#!/bin/bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
echo "---"
TOKEN=$(curl -s -X POST http://localhost:7070/api/auth/login -H "Content-Type: application/json" -d '{"username":"049094008190","password":"123456"}' | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('data',{}).get('token','') or d.get('token',''))" 2>/dev/null)
echo "TOKEN_LEN=${#TOKEN}"
echo "TOKEN_HEAD=${TOKEN:0:40}"
echo "BIRTHDAYS:"
curl -s http://localhost:7070/api/employees/birthdays -H "Authorization: Bearer $TOKEN" | head -c 2000
echo ""
echo "---"
docker logs --tail 30 zkteco_api 2>&1 | grep -i "Now listening\|http\|url" | head -5
