#!/bin/bash
# Try demo1 store with employee account
RAW=$(curl -s -X POST http://localhost:7070/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"storeCode":"demo1","userName":"an-demo1@demo.local","password":"Demo@123"}')
echo "LOGIN1: $(echo $RAW | head -c 300)"

TOKEN=$(echo "$RAW" | grep -o '"accessToken":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "TOKEN_LEN=${#TOKEN}"

if [ -z "$TOKEN" ]; then
  # Try demo1 store owner
  RAW=$(curl -s -X POST http://localhost:7070/api/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"storeCode":"demo1","userName":"demo1@gmail.com","password":"Demo@123"}')
  echo "LOGIN2: $(echo $RAW | head -c 300)"
  TOKEN=$(echo "$RAW" | grep -o '"accessToken":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "TOKEN_LEN=${#TOKEN}"
fi

if [ -z "$TOKEN" ]; then
  RAW=$(curl -s -X POST http://localhost:7070/api/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"storeCode":"demo1","userName":"demo1@gmail.com","password":"Ti100600@"}')
  echo "LOGIN3: $(echo $RAW | head -c 300)"
  TOKEN=$(echo "$RAW" | grep -o '"accessToken":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "TOKEN_LEN=${#TOKEN}"
fi

if [ -z "$TOKEN" ]; then
  echo "ALL LOGIN FAILED"; exit 1
fi

echo ""
echo "=== GET /locations ==="
curl -s http://localhost:7070/api/field-checkin/locations -H "Authorization: Bearer $TOKEN" | head -c 500
echo ""

echo "=== POST /locations (register) ==="
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

echo "=== POST /journey/start ==="
curl -s -X POST http://localhost:7070/api/field-checkin/journey/start -H "Authorization: Bearer $TOKEN" | head -c 300
echo ""

echo "ALL DONE"
