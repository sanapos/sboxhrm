#!/bin/bash
set -e
# Login
TOKEN=$(curl -s -X POST https://sbox.sana.vn/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"storeCode":"truongphat","email":"ngthihanh2011@gmail.com","password":"Admin123@"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('data',{}).get('accessToken',''); print(t[:20] + '...' if t else 'NO_TOKEN')")
echo "Token: $TOKEN"
# Test attendance correction
RESULT=$(curl -s -X POST https://sbox.sana.vn/api/AttendanceCorrections \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"employeeCode\":\"NV001\",\"requestDate\":\"2026-05-31\",\"correctionType\":\"Add\",\"newCheckIn\":\"08:00\",\"reason\":\"Test\"}")
echo "Result: $RESULT" | cut -c1-300