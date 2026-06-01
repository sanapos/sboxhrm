#!/bin/bash
echo "Testing login..."
curl -s -X POST "https://sbox.sana.vn/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"storeCode":"truongphat","userName":"ngthihanh2011@gmail.com","password":"Admin123@"}' \
  -o /tmp/login.json -w "HTTP:%{http_code}\n"
cat /tmp/login.json | head -c 300
echo ""