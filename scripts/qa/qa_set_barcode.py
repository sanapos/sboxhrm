"""Gán mã vạch cho hàng của cửa hàng test: python -I scripts/qa/qa_set_barcode.py Restaurant HH00005 8934567890123"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_e2e as q  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
ind, code, barcode = sys.argv[1], sys.argv[2], sys.argv[3]
base = 'http://127.0.0.1:7070'
_, _, _, token = q.login(base, q.load_accounts()[ind])
api = q.Api(base, token)
st, js, ms = api.call('GET', f'/api/pos/products?search={code}&page=1&pageSize=5')
d = q.data(js)
items = d.get('items') if isinstance(d, dict) else d
p = next(x for x in items if x.get('productCode') == code)
st, js, ms = api.call('GET', f"/api/pos/products/{p['id']}")
full = q.data(js)
full['barcode'] = barcode
st, js, ms = api.call('PUT', f"/api/pos/products/{p['id']}", full)
print(code, '→', barcode, 'HTTP', st, '' if q.ok_resp(st, js) else q.msg(js))
