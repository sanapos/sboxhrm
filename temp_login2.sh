#!/bin/bash
echo "--- LOGIN RAW ---"
curl -s -w '\nHTTP_CODE:%{http_code}' http://localhost:7070/api/auth/login -X POST -H 'Content-Type: application/json' -d '{"storeCode":"demo","userName":"demo@gmail.com","password":"Admin@123"}'
echo ""
echo "--- END ---"