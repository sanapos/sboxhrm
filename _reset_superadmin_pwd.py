#!/usr/bin/env python3
"""Reset SuperAdmin password using ASP.NET Identity V3 PBKDF2 hash format."""
import base64, hashlib, os, struct, subprocess, sys

EMAIL = "sanapos.vn@gmail.com"
NEW_PASSWORD = "123456aA@"

def hash_password_v3(password: str) -> str:
    # ASP.NET Core Identity V3: SHA512 / 100000 iter / 16-byte salt / 32-byte subkey
    prf = 2  # 0=SHA1, 1=SHA256, 2=SHA512
    iter_count = 100000
    salt_size = 16
    subkey_len = 32
    salt = os.urandom(salt_size)
    subkey = hashlib.pbkdf2_hmac("sha512", password.encode("utf-8"), salt, iter_count, dklen=subkey_len)
    payload = bytes([0x01]) + struct.pack(">I", prf) + struct.pack(">I", iter_count) + struct.pack(">I", salt_size) + salt + subkey
    return base64.b64encode(payload).decode("ascii")

def psql(sql: str) -> str:
    res = subprocess.run(
        ["docker", "exec", "-i", "zkteco_postgres", "psql", "-U", "postgres", "-d", "ZKTecoADMS", "-tA", "-c", sql],
        capture_output=True, text=True, check=True,
    )
    return res.stdout.strip()

def psql_quoted(sql_template: str, params: dict) -> str:
    # Use parameter substitution via psql variables to avoid quoting issues
    args = ["docker", "exec", "-i", "zkteco_postgres", "psql", "-U", "postgres", "-d", "ZKTecoADMS", "-tA"]
    for k, v in params.items():
        args += ["-v", f"{k}={v}"]
    args += ["-c", sql_template]
    res = subprocess.run(args, capture_output=True, text=True, check=True)
    return res.stdout.strip()

# 1. Find user
user_id = psql(f"SELECT \"Id\" FROM \"AspNetUsers\" WHERE LOWER(\"Email\") = LOWER('{EMAIL}') LIMIT 1;")
if not user_id:
    print(f"ERROR: User {EMAIL} not found", file=sys.stderr)
    sys.exit(1)
print(f"Found user Id = {user_id}")

# 2. Compute new hash
new_hash = hash_password_v3(NEW_PASSWORD)
print(f"New hash: {new_hash[:40]}... ({len(new_hash)} chars)")

# 3. Update PasswordHash + new SecurityStamp + clear lockout
import uuid
new_stamp = uuid.uuid4().hex.upper()

sql = (
    f"UPDATE \"AspNetUsers\" SET "
    f"\"PasswordHash\" = '{new_hash}', "
    f"\"SecurityStamp\" = '{new_stamp}', "
    f"\"AccessFailedCount\" = 0, "
    f"\"LockoutEnd\" = NULL, "
    f"\"PlainTextPassword\" = '{NEW_PASSWORD}' "
    f"WHERE \"Id\" = '{user_id}';"
)
out = psql(sql)
print(f"UPDATE OK: {out}")

# 4. Verify role
role = psql(
    f"SELECT r.\"Name\" FROM \"AspNetUserRoles\" ur "
    f"JOIN \"AspNetRoles\" r ON r.\"Id\" = ur.\"RoleId\" "
    f"WHERE ur.\"UserId\" = '{user_id}';"
)
print(f"Roles: {role or '(none)'}")
print("DONE")
