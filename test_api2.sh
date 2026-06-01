#!/bin/bash
set -e
echo "=== Test Login ==="
LOGIN_RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST https://sbox.sana.vn/api/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"storeCode\":\"truongphat\",\"email\":\"ngthihanh2011@gmail.com\",\"password\":\"Admin123@\"}")
HTTP_CODE=$(echo "$LOGIN_RESP" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
BODY=$(echo "$LOGIN_RESP" | grep -v "HTTP_CODE:")
echo "HTTP: $HTTP_CODE"
echo "Body prefix: ${BODY:0:200}"

TOKEN=$(echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('accessToken',''))" 2>/dev/null || echo "")
echo "Token (first 20): ${TOKEN:0:20}..."

if [ -z "$TOKEN" ]; then
  echo "LOGIN FAILED - checking account status"
  docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT \"UserName\", \"AccessFailedCount\", \"LockoutEnd\", \"LockoutEnabled\" FROM \"AspNetUsers\" WHERE \"UserName\"='ngthihanh2011@gmail.com';" 2>&1 || echo "psql query failed"
  exit 1
fi

echo ""
echo "=== Test AttendanceCorrection (Add) ==="
RESULT=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST https://sbox.sana.vn/api/AttendanceCorrections \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"employeeCode\":\"NV001\",\"requestDate\":\"2026-05-31\",\"correctionType\":\"Add\",\"newCheckIn\":\"08:00\",\"reason\":\"Test migration fix\"}")
HTTP2=$(echo "$RESULT" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
BODY2=$(echo "$RESULT" | grep -v "HTTP_CODE:")
echo "HTTP: $HTTP2"
echo "Body: ${BODY2:0:500}"