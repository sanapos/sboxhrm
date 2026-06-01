#!/bin/bash
# Generate ASP.NET Identity v3 password hash using Python
NEW_PASS="SboxAdmin@2026"
HASH=$(python3 -c "
import hashlib, os, struct, base64
password = '$NEW_PASS'
salt = os.urandom(16)
iterations = 310000
dk = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'), salt, iterations, dklen=32)
# Format: version(1) + prf_int32_be(4) + iter_int32_be(4) + saltlen_int32_be(4) + salt(16) + dk(32) = 61 bytes
b = bytes([0x01]) + struct.pack('>I', 1) + struct.pack('>I', iterations) + struct.pack('>I', 16) + salt + dk
print(base64.b64encode(b).decode())
")
echo "Generated hash for '$NEW_PASS'"
echo "Hash: $HASH"

# Update in DB
cat > /tmp/reset_pw.sql << SQLEOF
UPDATE "AspNetUsers"
SET "PasswordHash" = '$HASH',
    "SecurityStamp" = gen_random_uuid()::text,
    "AccessFailedCount" = 0,
    "LockoutEnd" = NULL
WHERE "UserName" = 'ngthihanh2011@gmail.com';
SQLEOF
docker cp /tmp/reset_pw.sql zkteco_postgres:/tmp/reset_pw.sql
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/reset_pw.sql
echo "Password reset done"

# Test login with new password
echo "--- Test login ---"
curl -s -X POST "https://sbox.sana.vn/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"storeCode\":\"truongphat\",\"userName\":\"ngthihanh2011@gmail.com\",\"password\":\"$NEW_PASS\"}" | head -c 200