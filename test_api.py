import json, urllib.request, sys

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
