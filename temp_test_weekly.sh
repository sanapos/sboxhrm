#!/bin/bash
TOKEN=$(curl -s -X POST http://localhost:7070/api/auth/login -H 'Content-Type: application/json' -d '{"userName":"demo@gmail.com","password":"Admin@123","storeCode":"demo"}' | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("data",{}).get("accessToken","none"))')
echo "TOKEN_PREFIX=${TOKEN:0:30}"
curl -s "http://localhost:7070/api/meals/menu/weekly?weekStartDate=2026-04-13" -H "Authorization: Bearer $TOKEN" | python3 -m json.tool 2>&1 | head -60
