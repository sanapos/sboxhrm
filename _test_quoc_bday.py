#!/usr/bin/env python3
"""Test birthdays endpoint as Quoc (Manager)."""
import base64, hashlib, json, os, struct, subprocess, urllib.request, uuid

USERNAME = "049094008190"
TEMP_PWD = "TempTest123@"
STORE_CODE = "demo"

def hash_password_v3(p):
    salt = os.urandom(16)
    subkey = hashlib.pbkdf2_hmac("sha512", p.encode(), salt, 100000, dklen=32)
    payload = bytes([0x01]) + struct.pack(">I", 2) + struct.pack(">I", 100000) + struct.pack(">I", 16) + salt + subkey
    return base64.b64encode(payload).decode()

def psql(sql):
    r = subprocess.run(["docker","exec","-i","zkteco_postgres","psql","-U","postgres","-d","ZKTecoADMS","-tA","-c",sql], capture_output=True, text=True, check=True)
    return r.stdout.strip()

# 1) Save original hash + stamp
orig = psql(f"SELECT \"PasswordHash\" || '|' || \"SecurityStamp\" FROM \"AspNetUsers\" WHERE \"UserName\"='{USERNAME}';")
orig_hash, orig_stamp = orig.split('|', 1)
print(f"Saved original hash len={len(orig_hash)}")

try:
    # 2) Set temp password
    new_hash = hash_password_v3(TEMP_PWD)
    new_stamp = uuid.uuid4().hex.upper()
    psql(f"UPDATE \"AspNetUsers\" SET \"PasswordHash\"='{new_hash}', \"SecurityStamp\"='{new_stamp}', \"AccessFailedCount\"=0, \"LockoutEnd\"=NULL WHERE \"UserName\"='{USERNAME}';")
    print("Temp password set")

    # 3) Login
    body = json.dumps({"storeCode": STORE_CODE, "userName": USERNAME, "password": TEMP_PWD}).encode()
    req = urllib.request.Request("http://localhost:7070/api/auth/login", data=body, headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req) as r:
        login = json.loads(r.read())
    token = login.get("accessToken") or login.get("data",{}).get("accessToken") or login.get("data",{}).get("token") or login.get("token")
    print(f"Login OK, token len={len(token) if token else 0}")
    print(f"Login response keys: {list(login.get('data',{}).keys()) if 'data' in login else list(login.keys())}")

    # 4) Call birthdays endpoint
    req2 = urllib.request.Request("http://localhost:7070/api/employees/birthdays", headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req2) as r:
            bd = json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode()[:500]}")
        bd = None
    if bd is None:
        items = None
    else:
        items = bd.get("data") if isinstance(bd, dict) else bd
    print(f"Birthdays count: {len(items) if isinstance(items, list) else 'N/A'}")
    if isinstance(bd, dict): print(f"Response: {json.dumps(bd)[:300]}")
    if isinstance(items, list):
        for e in items:
            name = f"{e.get('lastName','')} {e.get('firstName','')}"
            dob = e.get('dateOfBirth','')
            dept = e.get('department','')
            print(f"  - {name.strip()} | DOB={dob} | Dept={dept}")
finally:
    # 5) Restore
    psql(f"UPDATE \"AspNetUsers\" SET \"PasswordHash\"='{orig_hash}', \"SecurityStamp\"='{orig_stamp}' WHERE \"UserName\"='{USERNAME}';")
    print("Original password restored")
