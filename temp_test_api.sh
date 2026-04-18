#!/bin/bash
# Get auth token
TOKEN=$(curl -s -X POST http://localhost:7070/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"Admin@123"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('accessToken',''))" 2>/dev/null)

echo "Token: ${TOKEN:0:30}..."

# Test dishes endpoint with token
echo "=== GET /api/meals/dishes ==="
curl -s -w '\nHTTP %{http_code}' http://localhost:7070/api/meals/dishes -H "Authorization: Bearer $TOKEN" | tail -5

echo ""
echo "=== GET /api/meals/sessions ==="  
curl -s -w '\nHTTP %{http_code}' http://localhost:7070/api/meals/sessions -H "Authorization: Bearer $TOKEN" | tail -5

echo ""
echo "=== POST /api/meals/dishes ==="
curl -s -w '\nHTTP %{http_code}' -X POST http://localhost:7070/api/meals/dishes \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Test Dish","category":"Test","sortOrder":0}' | tail -5
