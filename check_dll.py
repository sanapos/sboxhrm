import sys

data = open("/tmp/ZKTecoADMS.Application.dll", "rb").read()
searches = [b"Before AddAsync", b"CreateLeave", b"LogWarning", b"request.ShiftIds", b"new Leave"]
for s in searches:
    found = s in data
    print(f"  {s.decode()}: {found}")
    if not found:
        # Try UTF-16
        s16 = s.decode().encode("utf-16-le")
        found16 = s16 in data
        print(f"  {s.decode()} (UTF-16): {found16}")
