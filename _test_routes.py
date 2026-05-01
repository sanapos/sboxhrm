#!/usr/bin/env python3
"""Test multiple endpoints as Quoc."""
import base64, hashlib, json, os, struct, subprocess, urllib.request, urllib.error, uuid

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

orig = psql(f"SELECT \"PasswordHash\" || '|' || \"SecurityStamp\" FROM \"AspNetUsers\" WHERE \"UserName\"='{USERNAME}';")
orig_hash, orig_stamp = orig.split('|', 1)
try:
    new_hash = hash_password_v3(TEMP_PWD)
    new_stamp = uuid.uuid4().hex.upper()
    psql(f"UPDATE \"AspNetUsers\" SET \"PasswordHash\"='{new_hash}', \"SecurityStamp\"='{new_stamp}', \"AccessFailedCount\"=0, \"LockoutEnd\"=NULL WHERE \"UserName\"='{USERNAME}';")

    body = json.dumps({"storeCode": STORE_CODE, "userName": USERNAME, "password": TEMP_PWD}).encode()
    req = urllib.request.Request("http://localhost:7070/api/auth/login", data=body, headers={"Content-Type":"application/json"})
    with urllib.request.urlopen(req) as r:
        login = json.loads(r.read())
    print(f"Login resp: {json.dumps(login)[:300]}")
    token = login.get("accessToken") or (login.get("data") or {}).get("accessToken")
    print(f"Token OK len={len(token)}")

    for path in ["/api/employees/birthdays"]:
        req2 = urllib.request.Request(f"http://localhost:7070{path}", headers={"Authorization": f"Bearer {token}"})
        try:
            with urllib.request.urlopen(req2) as r:
                data = json.loads(r.read())
                items = data.get("data", [])
                print(f"{path}: {len(items)} employees")
                for e in items:
                    name = f"{e.get('lastName','')} {e.get('firstName','')}".strip()
                    dob = e.get('dateOfBirth','')
                    dept = e.get('department','')
                    print(f"  - {name} | DOB={dob} | Dept={dept}")
        except urllib.error.HTTPError as e:
            print(f"{path} -> {e.code}: {e.read().decode()[:200]}")
finally:
    psql(f"UPDATE \"AspNetUsers\" SET \"PasswordHash\"='{orig_hash}', \"SecurityStamp\"='{orig_stamp}' WHERE \"UserName\"='{USERNAME}';")
    print("Restored")
