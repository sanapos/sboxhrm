"""Gọi nhanh 1 API của server test bằng tài khoản cửa hàng test: python -I scripts/qa/qa_call.py Restaurant GET /api/pos/sales/products"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_e2e as q  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
ind, method, path = sys.argv[1], sys.argv[2], sys.argv[3]
raw = sys.argv[4] if len(sys.argv) > 4 else None
if raw and raw.startswith('@'):  # @đường_dẫn.json — tránh lỗi trích dẫn JSON trên PowerShell
    with open(raw[1:], encoding='utf-8-sig') as f:
        raw = f.read()
body = json.loads(raw) if raw else None
base = 'http://127.0.0.1:7070'
acc = q.load_accounts()
_, _, _, token = q.login(base, acc[ind])
st, js, ms = q.Api(base, token).call(method, path, body)
print(f'HTTP {st} {ms:.0f}ms')
print(json.dumps(js, ensure_ascii=False, indent=1)[:4000])
