#!/bin/bash
# Login
TOKEN=$(curl -s -X POST "https://sbox.sana.vn/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"storeCode":"truongphat","userName":"ngthihanh2011@gmail.com","password":"SboxAdmin@2026"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['accessToken'])" 2>/dev/null)
echo "Token OK: ${#TOKEN} chars"

echo ""
echo "=== Test 1: Create AttendanceCorrection (Add) ==="
RES1=$(curl -s -X POST "https://sbox.sana.vn/api/AttendanceCorrections" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"employeeCode":"NV001","requestDate":"2026-05-31","correctionType":"Add","newCheckIn":"08:00:00","reason":"Test migration fix"}')
echo "Result: $(echo $RES1 | head -c 400)"

echo ""
echo "=== Test 2: Manual Attendance ==="
# Get first employee GUID
EMP_GUID=$(docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -t -A -c "SELECT \"EmployeeGuid\" FROM \"Employees\" WHERE \"EmployeeCode\" IS NOT NULL LIMIT 1;" 2>/dev/null | tr -d ' ')
echo "Employee GUID: $EMP_GUID"
if [ -n "$EMP_GUID" ] && [ "$EMP_GUID" != "null" ]; then
  RES2=$(curl -s -X POST "https://sbox.sana.vn/api/attendances/manual" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "{\"employeeGuid\":\"$EMP_GUID\",\"punchTime\":\"2026-05-31T08:00:00\",\"punchType\":\"CheckIn\"}")
  echo "Manual attendance result: $(echo $RES2 | head -c 400)"
fi