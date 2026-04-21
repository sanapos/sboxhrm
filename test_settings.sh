#!/bin/bash
TOKEN=$(cat /tmp/sa_token.txt)
echo 'eyJrZXkiOiJHb29nbGVEcml2ZUVuYWJsZWQiLCJ2YWx1ZSI6InRydWUiLCJncm91cCI6InN5c3RlbSIsImRhdGFUeXBlIjoic3RyaW5nIn0=' | base64 -d > /tmp/gtest.json
echo "=== POST /api/settings/app ==="
curl -s -X POST http://127.0.0.1:7070/api/settings/app -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d @/tmp/gtest.json | jq .
echo "=== POST /api/system-admin/settings ==="
curl -s -X POST http://127.0.0.1:7070/api/system-admin/settings -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d @/tmp/gtest.json | jq .