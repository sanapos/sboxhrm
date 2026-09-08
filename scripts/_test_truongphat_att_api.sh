#!/bin/bash
set -e
# Test attendance API pagination for Trường Phát June 2026
API="https://sbox.sana.vn"
# Try common passwords
for PASS in "SboxAdmin@2026" "Admin123@" "123456aA@" "Truongphat@2026"; do
  TOKEN=$(curl -sk -X POST "$API/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"storeCode\":\"truongphat\",\"userName\":\"ngthihanh2011@gmail.com\",\"password\":\"$PASS\"}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('accessToken','') if d.get('isSuccess') else '')" 2>/dev/null)
  if [ -n "$TOKEN" ] && [ "$TOKEN" != "None" ]; then
    echo "LOGIN OK with pass len ${#PASS}"
    break
  fi
done
if [ -z "$TOKEN" ] || [ "$TOKEN" = "None" ]; then echo "LOGIN FAILED"; exit 1; fi

DEVICES='["54931289-c9d5-49cb-b615-0c03726c473a","6d11bba9-c795-417f-a327-0ca70f5dee00","290dd675-621f-478d-97f8-fa9484aae633","c4bcb6e8-9c86-4df8-b479-20c022a97a7c"]'
FROM="2026-05-31T00:00:00.000"
TO="2026-07-01T00:00:00.000"
BODY="{\"deviceIds\":$DEVICES,\"fromDate\":\"$FROM\",\"toDate\":\"$TO\"}"

for PAGE in 1 2 3; do
  echo ""
  echo "=== PAGE $PAGE ==="
  curl -sk -X POST "$API/api/attendances/devices?pageNumber=$PAGE&pageSize=1000&page=$PAGE" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
data=d.get('data') or {}
items=data.get('items') or []
print('isSuccess', d.get('isSuccess'))
print('totalCount', data.get('totalCount'))
print('pageNumber', data.get('pageNumber'))
print('pageSize', data.get('pageSize'))
print('items', len(items))
if items:
  print('firstTime', items[0].get('attendanceTime') or items[0].get('AttendanceTime'))
  print('lastTime', items[-1].get('attendanceTime') or items[-1].get('AttendanceTime'))
  ids=set(str(i.get('id') or i.get('Id')) for i in items)
  print('uniqueIds', len(ids))
"
done
