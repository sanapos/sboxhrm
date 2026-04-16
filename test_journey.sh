#!/bin/bash
# Login
RAW=$(curl -s -X POST http://localhost:7070/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"storeCode":"demo","userName":"demo@gmail.com","password":"Demo@123"}')
TOKEN=$(echo "$RAW" | grep -o '"accessToken":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "TOKEN_LEN=${#TOKEN}"

if [ -z "$TOKEN" ]; then
  RAW=$(curl -s -X POST http://localhost:7070/api/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"storeCode":"demo1","userName":"an-demo1@demo.local","password":"Demo@123"}')
  TOKEN=$(echo "$RAW" | grep -o '"accessToken":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "TOKEN2_LEN=${#TOKEN}"
fi

H="Authorization: Bearer $TOKEN"

echo ""
echo "=== GET journey/today ==="
curl -s http://localhost:7070/api/field-checkin/journey/today -H "$H" | python3 -m json.tool 2>/dev/null || curl -s http://localhost:7070/api/field-checkin/journey/today -H "$H"

echo ""
echo "=== POST journey/start ==="
curl -s -X POST http://localhost:7070/api/field-checkin/journey/start -H "$H" | python3 -m json.tool 2>/dev/null || curl -s -X POST http://localhost:7070/api/field-checkin/journey/start -H "$H"

echo ""
echo "=== POST journey/track (2 points) ==="
curl -s -X POST http://localhost:7070/api/field-checkin/journey/track \
  -H "$H" -H 'Content-Type: application/json' \
  -d '{"points":[{"latitude":10.762622,"longitude":106.660172,"timestamp":"2026-04-14T14:00:00Z"},{"latitude":10.763622,"longitude":106.661172,"timestamp":"2026-04-14T14:01:00Z"}]}' | python3 -m json.tool 2>/dev/null || echo "TRACK FAILED"

echo ""
echo "=== POST journey/end ==="
ENDRESP=$(curl -s -w "\n%{http_code}" -X POST http://localhost:7070/api/field-checkin/journey/end \
  -H "$H" -H 'Content-Type: application/json' \
  -d '{"note":"test end"}')
ENDCODE=$(echo "$ENDRESP" | tail -1)
ENDBODY=$(echo "$ENDRESP" | sed '$d')
echo "HTTP $ENDCODE"
echo "$ENDBODY" | python3 -m json.tool 2>/dev/null || echo "$ENDBODY"

echo ""
echo "=== GET journey/today (after end) ==="
curl -s http://localhost:7070/api/field-checkin/journey/today -H "$H" | python3 -m json.tool 2>/dev/null || curl -s http://localhost:7070/api/field-checkin/journey/today -H "$H"
