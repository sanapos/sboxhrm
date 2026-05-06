import json, urllib.request, sys

# --- Quick test for lateEmployees bug ---
def test_late_employees():
    base = "http://localhost:7070"
    # Login with StoreCode (employee/admin account)
    credentials = [
        {"StoreCode": "demo", "UserName": "0358968314", "Password": "123456"},
        {"StoreCode": "demo", "UserName": "admin@gmail.com", "Password": "Ti100600@"},
        {"StoreCode": "demo", "UserName": "manager@gmail.com", "Password": "Ti100600@"},
    ]
    token = None
    for cred in credentials:
        req = urllib.request.Request(f"{base}/api/auth/login",
            data=json.dumps(cred).encode(),
            headers={"Content-Type":"application/json"})
        try:
            d = json.loads(urllib.request.urlopen(req).read())
            if d.get('isSuccess'):
                dd = d.get('data', {})
                token = dd.get('accessToken','') or dd.get('token','') if isinstance(dd,dict) else ''
                if token: print(f"Logged in as {cred['UserName']}"); break
        except Exception as e: print(f"Login {cred['UserName']} failed: {e}")
    if not token: print("All logins failed"); return
    print(f"Token len={len(token)}")
    # Get trends
    req2 = urllib.request.Request(f"{base}/api/dashboard/attendance-trends?days=14",
        headers={"Authorization": f"Bearer {token}"})
    try:
        raw = urllib.request.urlopen(req2).read()
        d2 = json.loads(raw)
    except urllib.error.HTTPError as e:
        print(f"Trends HTTP {e.code}: {e.read()[:400]}"); return
    except Exception as e:
        print(f"Trends error: {e}"); return
    trends = d2.get('data', [])
    print(f"items={len(trends)}")
    for t in trends:
        le = t.get('lateEmployees', None)
        ee = t.get('earlyEmployees', None)
        lat = t.get('late', 0)
        ear = t.get('earlyLeave', 0)
        le_count = len(le) if le is not None else 'MISSING_KEY'
        ee_count = len(ee) if ee is not None else 'MISSING_KEY'
        match = ("OK" if (lat == (le_count if isinstance(le_count,int) else -1)) else "MISMATCH!") 
        print(f"  {t['date']} late={lat} earlyLeave={ear} lateEmpCount={le_count} earlyEmpCount={ee_count} {match}")
        if le:
            for e in le[:2]: print(f"    late-> {e}")
        if ee:
            for e in ee[:2]: print(f"    early-> {e}")

if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1] == 'test_late':
    test_late_employees()
    sys.exit(0)
# --- end test ---

base = "http://localhost:7070"

# Try login with different passwords
passwords = ["Abc@123", "Admin@123", "1234567890", "123456", "Linh@@3103"]
token = None

# Try employee accounts with phone login
phone_users = ["0358968314", "0935364557", "0358968313"]
for phone in phone_users:
    for pw in passwords:
        try:
            data = json.dumps({"StoreCode": "demo", "UserName": phone, "Password": pw}).encode()
            req = urllib.request.Request(f"{base}/api/auth/login", data=data, headers={"Content-Type": "application/json"})
            resp = json.loads(urllib.request.urlopen(req).read())
            if resp.get("isSuccess"):
                token = resp["data"]["accessToken"]
                print(f"Logged in as {phone} with pw: {pw}")
                break
        except:
            pass
    if token:
        break

# Also try admin
if not token:
    for pw in passwords:
        try:
            data = json.dumps({"StoreCode": "demo", "UserName": "demo@gmail.com", "Password": pw}).encode()
            req = urllib.request.Request(f"{base}/api/auth/login", data=data, headers={"Content-Type": "application/json"})
            resp = json.loads(urllib.request.urlopen(req).read())
            if resp.get("isSuccess"):
                token = resp["data"]["accessToken"]
                print(f"Logged in as admin with pw: {pw}")
                break
            else:
                print(f"admin PW {pw}: {resp.get('message', '')[:40]}")
        except Exception as e:
            print(f"admin PW {pw}: {e}")

if not token:
    print("Could not login")
    sys.exit(1)

# Create leave with multiple shiftIds
leave_data = json.dumps({
    "shiftId": "1b17d7c0-d206-42d9-b973-baf0ae0ac3f2",
    "shiftIds": ["1b17d7c0-d206-42d9-b973-baf0ae0ac3f2", "a0f79a74-91de-42c5-93cf-eb463198646b"],
    "startDate": "2026-04-15T08:00:00",
    "endDate": "2026-04-15T17:00:00",
    "type": 0,
    "isHalfShift": False,
    "reason": "Test multi shift"
}).encode()
req2 = urllib.request.Request(f"{base}/api/Leaves", data=leave_data, headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"})
try:
    resp2 = json.loads(urllib.request.urlopen(req2).read())
    print(json.dumps(resp2, indent=2, default=str)[:1000])
except urllib.error.HTTPError as e:
    print(f"HTTP {e.code}: {e.read().decode()[:500]}")
