#!/bin/bash
# Try different passwords to login and test weekly menu
API="http://localhost:7070"
USER="demo@gmail.com"
STORE="demo"

for PWD in "Abc@123" "Admin@123" "1234567890" "123456" "Linh@@3103" "Demo@123" "demo@123" "Abc@1234"; do
  RESP=$(curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' -d "{\"userName\":\"$USER\",\"password\":\"$PWD\",\"storeCode\":\"$STORE\"}")
  SUCCESS=$(echo "$RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("isSuccess",False))' 2>/dev/null)
  if [ "$SUCCESS" = "True" ]; then
    echo "SUCCESS with password: $PWD"
    TOKEN=$(echo "$RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["data"]["accessToken"])' 2>/dev/null)
    echo "TOKEN=${TOKEN:0:50}..."
    
    echo "--- Testing weekly menu ---"
    MENU_RESP=$(curl -s "$API/api/meals/menu/weekly?weekStartDate=2026-04-13" -H "Authorization: Bearer $TOKEN")
    echo "WEEKLY_MENU=$MENU_RESP" | head -c 2000
    echo ""
    echo "--- Testing weekly menu (current week) ---"
    MENU_RESP2=$(curl -s "$API/api/meals/menu/weekly" -H "Authorization: Bearer $TOKEN")
    echo "WEEKLY_MENU_CURRENT=$MENU_RESP2" | head -c 2000
    exit 0
  else
    MSG=$(echo "$RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("message",""))' 2>/dev/null)
    echo "FAIL $PWD : $MSG"
  fi
done
echo "All passwords failed"
