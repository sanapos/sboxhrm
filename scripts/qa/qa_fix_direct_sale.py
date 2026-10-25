"""Bật «bán trực tiếp» cho mọi hàng của một cửa hàng test (dữ liệu tạo trước khi script gửi isDirectSale)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_e2e as q  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
ind = sys.argv[1]
base = 'http://127.0.0.1:7070'
_, _, _, token = q.login(base, q.load_accounts()[ind])
api = q.Api(base, token)
st, js, ms = api.call('GET', '/api/pos/products?page=1&pageSize=100')
d = q.data(js)
items = d.get('items') if isinstance(d, dict) else d
for p in items or []:
    st, js, ms = api.call('GET', f"/api/pos/products/{p['id']}")
    full = q.data(js)
    full['isDirectSale'] = True
    st, js, ms = api.call('PUT', f"/api/pos/products/{p['id']}", full)
    print(p.get('name'), 'HTTP', st, '' if q.ok_resp(st, js) else q.msg(js))
