#!/bin/bash
API="https://sbox.sana.vn"
PASS="123456aA@"
TOKEN=$(curl -sk -X POST "$API/api/auth/login" -H "Content-Type: application/json" \
  -d "{\"storeCode\":\"truongphat\",\"userName\":\"ngthihanh2011@gmail.com\",\"password\":\"$PASS\"}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('accessToken','') if d.get('isSuccess') else '')")
echo "token len ${#TOKEN}"
DEVICES='["54931289-c9d5-49cb-b615-0c03726c473a","6d11bba9-c795-417f-a327-0ca70f5dee00","290dd675-621f-478d-97f8-fa9484aae633","c4bcb6e8-9c86-4df8-b479-20c022a97a7c"]'
for RANGE in "strict_june|2026-06-01T00:00:00|2026-06-30T23:59:59" "client_fetch|2026-05-31T00:00:00|2026-07-01T00:00:00"; do
  IFS='|' read -r LABEL FROM TO <<< "$RANGE"
  BODY="{\"deviceIds\":$DEVICES,\"fromDate\":\"$FROM\",\"toDate\":\"$TO\"}"
  echo "=== $LABEL ($FROM -> $TO) ==="
  curl -sk -X POST "$API/api/attendances/devices?pageNumber=1&pageSize=1000&page=1" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$BODY" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); data=d.get('data') or {}; print('total', data.get('totalCount'), 'items', len(data.get('items') or []))"
done
