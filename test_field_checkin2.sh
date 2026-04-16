#!/bin/bash
# Test field-checkin endpoints  
RAW=$(curl -s -X POST http://localhost:7070/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@sbox.vn","password":"Sbox@2024"}')
echo "LOGIN RAW: $RAW" | head -c 200
echo ""

TOKEN=$(echo "$RAW" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "TOKEN_LEN=${#TOKEN}"

if [ -z "$TOKEN" ]; then
  echo "Trying superadmin..."
  RAW=$(curl -s -X POST http://localhost:7070/api/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"superadmin@sbox.vn","password":"Sbox@2024"}')
  echo "LOGIN RAW2: $RAW" | head -c 200
  echo ""
  TOKEN=$(echo "$RAW" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "TOKEN_LEN=${#TOKEN}"
fi

if [ -z "$TOKEN" ]; then
  echo "ALL LOGIN FAILED"
  exit 1
fi

echo ""
echo "=== GET /locations ==="
curl -s http://localhost:7070/api/field-checkin/locations -H "Authorization: Bearer $TOKEN" | head -c 500
echo ""

echo "=== POST /locations ==="
curl -s -X POST http://localhost:7070/api/field-checkin/locations \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Shop ABC","address":"123 Nguyen Trai","contactName":"Anh Minh","contactPhone":"0901234567","latitude":10.762622,"longitude":106.660172,"radius":200,"category":"retail"}' | head -c 500
echo ""

echo "=== GET /journey/today ==="
curl -s http://localhost:7070/api/field-checkin/journey/today -H "Authorization: Bearer $TOKEN" | head -c 300
echo ""

echo "=== GET /my-assignments ==="
curl -s http://localhost:7070/api/field-checkin/my-assignments -H "Authorization: Bearer $TOKEN" | head -c 300
echo ""

echo "=== GET /today ==="
curl -s http://localhost:7070/api/field-checkin/today -H "Authorization: Bearer $TOKEN" | head -c 300
echo ""
echo "ALL DONE"
