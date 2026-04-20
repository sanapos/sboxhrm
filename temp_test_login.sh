#!/bin/bash
# Step 1: Test login
RESP=$(curl -s -X POST http://localhost:7070/api/auth/login -H 'Content-Type: application/json' -d '{"userName":"demo@gmail.com","password":"Admin@123","storeCode":"demo"}')
echo "LOGIN_RESP=${RESP:0:300}"
echo "---"

# Step 2: Extract token
TOKEN=$(echo "$RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("data",{}).get("accessToken","none"))' 2>&1)
echo "TOKEN=${TOKEN:0:40}"
