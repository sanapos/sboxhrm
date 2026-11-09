"""Ghép dữ liệu cho test/store_shots (ảnh App Store SBOX BOSS).

Nguồn: flutter_client/test/store_shots/fixtures
  - modules.txt: quyền / gói module của chủ cửa hàng demopos («Mã~Tên~Thứ tự|…»).
  - resp/*.json: phản hồi API chép từ demopos trên sboxpos.com
    ({"GET /api/x": {"status": 200, "body": "<json>"}}; khóa không có ?query thì khớp mọi query).
Ra: flutter_client/build/store_shots/fx/{fixtures.json,user.json} + phiên giả (JWT không ký,
chỉ để app không tự đăng xuất trong test — không phải khóa thật).
"""
import base64
import json
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "flutter_client" / "test" / "store_shots" / "fixtures"
OUT = ROOT / "flutter_client" / "build" / "store_shots" / "fx"
USER_ID = "a555b26a-cea1-4606-9a3f-e0e003a9e6b8"
STORE_ID = "55300345-026c-4e82-97ed-13e7dcfd2c54"


def ok(data):
    return {"status": 200, "body": json.dumps({"isSuccess": True, "errors": [], "message": "", "data": data},
                                              ensure_ascii=False)}


def b64(o):
    return base64.urlsafe_b64encode(json.dumps(o).encode()).rstrip(b"=").decode()


def fake_jwt():
    now = int(time.time())
    claims = {
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier": USER_ID,
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress": "demopos@gmail.com",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name": "Demo POS Owner",
        "http://schemas.microsoft.com/ws/2008/06/identity/claims/role": "Admin",
        "storeId": STORE_ID, "storeName": "Demo POS", "userName": "demopos@gmail.com",
        "employeeId": "", "exp": now + 30 * 86400, "iat": now, "nbf": now,
    }
    return f"{b64({'alg': 'none', 'typ': 'JWT'})}.{b64(claims)}.x"


def main():
    mods = (SRC / "modules.txt").read_text(encoding="utf-8").strip().split("|")
    codes = [m.split("~")[0] for m in mods]
    perms = []
    for i, m in enumerate(mods):
        code, name, order = m.split("~")
        perms.append({"permissionId": f"00000000-0000-0000-0000-{i:012d}", "module": code, "moduleDisplayName": name,
                      "displayOrder": int(order), "canView": True, "canCreate": True, "canEdit": True,
                      "canDelete": True, "canExport": True, "canApprove": True})
    fx = {
        "GET /api/permission-management/my-permissions": ok(perms),
        "GET /api/settings/my-modules": ok([c for c in codes if c not in ("PosHub", "PosReport")]),
        "POST /api/auth/refresh": ok({"accessToken": fake_jwt(), "refreshToken": "shot-refresh"}),
    }
    for f in sorted((SRC / "resp").glob("*.json")):
        fx.update(json.loads(f.read_text(encoding="utf-8")))
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "fixtures.json").write_text(json.dumps(fx, ensure_ascii=False), encoding="utf-8")
    (OUT / "user.json").write_text(json.dumps({"id": USER_ID, "email": "demopos@gmail.com", "fullName": "Demo POS Owner",
                                               "storeId": STORE_ID, "allowedModules": codes}, ensure_ascii=False),
                                   encoding="utf-8")
    print(len(fx), "fixtures ->", OUT)


main()
