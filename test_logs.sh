#!/bin/bash
# Create a correction request and immediately check logs
TOKEN=$(curl -s -X POST "https://sbox.sana.vn/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"storeCode":"truongphat","userName":"ngthihanh2011@gmail.com","password":"SboxAdmin@2026"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['accessToken'])" 2>/dev/null)

echo "=== Creating correction request ==="
BEFORE_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
sleep 1
RESULT=$(curl -s -X POST "https://sbox.sana.vn/api/AttendanceCorrections" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"employeeCode":"NV001","requestDate":"2026-05-31","correctionType":"Add","newDate":"2026-05-31","newTime":"10:00:00","reason":"AutoApprove test2"}')
echo "Status from API: $(echo $RESULT | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('status','?'))" 2>/dev/null)"
sleep 2

echo ""
echo "=== API logs (last 30 lines, errors/warnings) ==="
docker logs zkteco_api --since 20s 2>&1 | tail -30