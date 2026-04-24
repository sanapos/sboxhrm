#!/bin/bash
TOKEN=$(curl -sk -X POST https://sbox.sana.vn/api/auth/AdminLogin \
  -H 'Content-Type: application/json' \
  -d '{"userName":"sanapos.vn@gmail.com","password":"123456aA@"}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["accessToken"])')
echo "Token length: ${#TOKEN}"
echo "--- Calling DELETE ---"
curl -sk -X DELETE "https://sbox.sana.vn/api/system-admin/stores/113d5e1f-ff6f-46b3-b842-b2aac050b7f5?confirmDelete=true" \
  -H "Authorization: Bearer $TOKEN" \
  -w "\nHTTP %{http_code}\n"
