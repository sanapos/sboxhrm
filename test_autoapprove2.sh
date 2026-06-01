#!/bin/bash
TOKEN=$(curl -s -X POST "https://sbox.sana.vn/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"storeCode":"truongphat","userName":"ngthihanh2011@gmail.com","password":"SboxAdmin@2026"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['accessToken'])" 2>/dev/null)

echo "=== Test auto-approve with Admin account ==="
RESULT=$(curl -s -X POST "https://sbox.sana.vn/api/AttendanceCorrections" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"employeeCode":"NV001","correctionType":"Add","newDate":"2026-05-31","newTime":"08:00:00","reason":"Test auto approve after fix"}')

STATUS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','?'))" 2>/dev/null)
echo "Status returned: $STATUS"
echo "Full: $RESULT"