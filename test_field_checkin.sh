#!/bin/bash
# Test field-checkin endpoints
TOKEN=$(curl -s -X POST http://localhost:7070/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@sbox.vn","password":"Sbox@2024"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('token',''))" 2>/dev/null)

echo "TOKEN_LEN=${#TOKEN}"
if [ -z "$TOKEN" ]; then
  echo "Login failed, trying other creds..."
  TOKEN=$(curl -s -X POST http://localhost:7070/api/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"superadmin@sbox.vn","password":"Sbox@2024"}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('token',''))" 2>/dev/null)
  echo "TOKEN_LEN=${#TOKEN}"
fi

echo ""
echo "=== GET /locations ==="
curl -s http://localhost:7070/api/field-checkin/locations \
  -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d,indent=2,ensure_ascii=False)[:500])" 2>/dev/null

echo ""
echo "=== GET /journey/today ==="
curl -s http://localhost:7070/api/field-checkin/journey/today \
  -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d,indent=2,ensure_ascii=False)[:300])" 2>/dev/null

echo ""
echo "=== GET /my-assignments ==="
curl -s http://localhost:7070/api/field-checkin/my-assignments \
  -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d,indent=2,ensure_ascii=False)[:300])" 2>/dev/null

echo ""
echo "=== GET /today ==="
curl -s http://localhost:7070/api/field-checkin/today \
  -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d,indent=2,ensure_ascii=False)[:300])" 2>/dev/null

echo ""
echo "=== POST /locations (register) ==="
curl -s -X POST http://localhost:7070/api/field-checkin/locations \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Shop ABC","address":"123 Nguyen Trai","contactName":"Anh Minh","contactPhone":"0901234567","latitude":10.762622,"longitude":106.660172,"radius":200,"category":"retail"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d,indent=2,ensure_ascii=False)[:500])" 2>/dev/null

echo ""
echo "DONE"
