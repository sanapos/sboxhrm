#!/bin/bash
# Login
TOKEN=$(curl -s -X POST "https://sbox.sana.vn/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"storeCode":"truongphat","userName":"ngthihanh2011@gmail.com","password":"SboxAdmin@2026"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['accessToken'])" 2>/dev/null)

# Test create correction and get FULL response
echo "=== Create AttendanceCorrection ==="
RESULT=$(curl -s -X POST "https://sbox.sana.vn/api/AttendanceCorrections" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"employeeCode":"NV001","requestDate":"2026-05-31","correctionType":"Add","newCheckIn":"09:00:00","newDate":"2026-05-31","newTime":"09:00:00","reason":"AutoApprove test"}')
echo "Full result: $RESULT"
echo ""
# Check status in DB
REQ_ID=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('id',''))" 2>/dev/null)
echo "Request ID: $REQ_ID"
if [ -n "$REQ_ID" ]; then
  docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -t -A -c "SELECT \"Status\", \"CurrentApprovalStep\", \"TotalApprovalLevels\" FROM \"AttendanceCorrectionRequests\" WHERE \"Id\"='$REQ_ID';"
fi