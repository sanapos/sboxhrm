"""Chạy trọn luồng AhaMove qua API QA 7073 + máy chủ AhaMove giả 7099. In kết quả từng bước."""
import json
import os
import secrets
import sys
import urllib.request

sys.path.insert(0, r'E:\SBOX CURSOR\ZKTecoADMS-master\scripts\qa')
import qa_e2e as q  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
BASE = 'http://127.0.0.1:7073'
MOCK = 'http://127.0.0.1:7099'
HERE = os.path.dirname(os.path.abspath(__file__))
MOCK_LOG = os.path.join(HERE, 'aha_mock.jsonl')
if os.path.exists(MOCK_LOG):
    os.remove(MOCK_LOG)

acc = q.load_accounts()['Retail']
st, js, ms, token = q.login(BASE, acc)
assert token, f'login fail {st} {js}'
api = q.Api(BASE, token)


def show(step, st, js, keys=None):
    d = js.get('data') if isinstance(js, dict) else None
    if keys and isinstance(d, dict):
        d = {k: d.get(k) for k in keys}
    msg = js.get('message') if isinstance(js, dict) else None
    print(f'\n## {step}: HTTP {st} isSuccess={js.get("isSuccess") if isinstance(js, dict) else None} msg={msg}')
    print(json.dumps(d, ensure_ascii=False)[:1500])
    return js.get('data') if isinstance(js, dict) else None


def mock(path, body=None):
    req = urllib.request.Request(MOCK + path, data=json.dumps(body or {}).encode(), method='POST')
    req.add_header('Content-Type', 'application/json')
    return json.loads(urllib.request.urlopen(req).read())


def mock_calls():
    if not os.path.exists(MOCK_LOG):
        return []
    with open(MOCK_LOG, encoding='utf-8') as f:
        return [json.loads(x) for x in f if x.strip()]


def token_calls():
    return sum(1 for c in mock_calls() if c['path'] == '/v3/accounts/token')


def webhook(body, query='', headers=None):
    req = urllib.request.Request(f'{BASE}/api/webhooks/shipping/Ahamove{query}',
                                 data=json.dumps(body).encode(), method='POST')
    req.add_header('Content-Type', 'application/json')
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        r = urllib.request.urlopen(req)
        return r.status, json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b'{}')


def events(oid):
    st, js, _ = api.call('GET', f'/api/pos/shipping/shipments/{oid}/events')
    d = (js or {}).get('data')
    return d


# 1. Cấu hình AhaMove trỏ về máy chủ giả
st, js, _ = api.call('PUT', '/api/pos/shipping/settings', {
    'carrierCode': 'Ahamove', 'enabled': True, 'useSandbox': True,
    'apiToken': 'qa-mock-api-key', 'shopId': '0928192214', 'apiBaseUrl': MOCK,
    'pickupName': 'QA Retail', 'pickupPhone': '0928192214', 'pickupAddress': '12 Bạch Đằng',
    'fromProvinceName': 'Đà Nẵng', 'fromWardName': 'Phường Hải Châu',
    'extraJson': json.dumps({'lat': 16.0678, 'lng': 108.2208, 'group_service_id': 'BIKE'}),
})
show('1 Lưu cấu hình AhaMove', st, js, ['carrierCode', 'enabled', 'hasApiToken', 'hasPassword', 'notice'])
print('   token calls so far:', token_calls())

st, js, _ = api.call('GET', '/api/pos/shipping/settings')
aha = next(x for x in js['data'] if x['carrierCode'] == 'Ahamove')
secret = aha.get('webhookSecret')
print('   webhookSecret có:', bool(secret), '| webhookUrl:', aha.get('webhookUrl'))

# 2. Tạo đơn giao hàng
st, js, _ = api.call('GET', '/api/pos/sales/products?page=1&pageSize=3')
d = js.get('data') or {}
items = d.get('items') if isinstance(d, dict) else d
prod = items[0]
pid = prod.get('id')
price = float(prod.get('salePrice') or prod.get('price') or 100000)
print(f'\n   SP thử: {prod.get("name")} giá {price}')


def new_delivery_order(tag):
    body = {'lines': [{'productId': pid, 'qty': 2, 'unitPrice': price, 'discount': 0}],
            'discount': 0, 'paidAmount': 0, 'paymentMethod': 'Cash', 'customerName': f'Khách QA Aha {tag}',
            'customerId': None, 'note': 'QA AhaMove', 'complete': False, 'clientRequestId': secrets.token_hex(8),
            'isDelivery': True, 'deliveryAddress': '20 Lê Lợi', 'deliveryPhone': '0905111222',
            'deliveryPartner': 'AhaMove', 'deliveryProvince': 'Đà Nẵng', 'deliveryWard': 'Phường Hải Châu'}
    st, js, _ = api.call('POST', '/api/pos/sales', body)
    d = show(f'2 Tạo đơn giao hàng {tag}', st, js, ['id', 'orderNo', 'total', 'status', 'isDelivery'])
    return d['id'], d.get('orderNo')


oid, ono = new_delivery_order('A')

# 3. Báo giá đơn lẻ
st, js, _ = api.call('POST', '/api/pos/shipping/quote', {
    'carrierCode': 'Ahamove', 'toName': 'Khách QA', 'toPhone': '0905111222', 'toAddress': '20 Lê Lợi',
    'toProvince': 'Đà Nẵng', 'toWard': 'Phường Hải Châu', 'codAmount': 200000})
show('3 Báo giá /quote', st, js, ['success', 'fee', 'serviceName', 'serviceCode', 'etaMinutes', 'message'])

# 4. So sánh hãng cho đơn
st, js, _ = api.call('POST', '/api/pos/shipping/compare', {'orderId': oid})
d = show('4 So sánh /compare', st, js, ['quotes'])
aq = next((x for x in (js.get('data') or {}).get('quotes', []) if x.get('carrierCode') == 'Ahamove'), None)
print('   AhaMove quote:', aq)

# 5. Tạo vận đơn
create = {'carrierCode': 'Ahamove', 'orderId': oid, 'serviceCode': (aq or {}).get('serviceCode'),
          'serviceName': (aq or {}).get('serviceName'), 'shipFeePayer': 'customer'}
st, js, _ = api.call('POST', '/api/pos/shipping/shipments', create)
d = show('5 Tạo vận đơn', st, js, ['success', 'trackingCode', 'carrierOrderId', 'fee', 'labelUrl', 'message'])
aha_id = d.get('trackingCode')
last_create = [c for c in mock_calls() if c['path'] == '/v3/orders'][-1]
print('   body gửi AhaMove:', json.dumps(last_create['body'], ensure_ascii=False)[:1200])

# 6. Bấm tạo lần 2
st, js, _ = api.call('POST', '/api/pos/shipping/shipments', create)
show('6 Tạo vận đơn lần 2 (phải chặn)', st, js, ['success', 'trackingCode', 'message'])

# 7. Link theo dõi
st, js, _ = api.call('GET', f'/api/pos/shipping/shipments/{oid}/label')
show('7 Theo dõi đơn /label', st, js, ['success', 'labelUrl', 'message'])

# 8. Đồng bộ hành trình (tài xế nhận)
mock(f'/__state/{aha_id}', {'status': 'ACCEPTED', 'sub_status': 'BOARDED'})
st, js, _ = api.call('POST', f'/api/pos/shipping/shipments/{oid}/sync-tracking')
show('8 Đồng bộ hành trình (ACCEPTED)', st, js, ['success', 'statusName', 'mappedOnlineStatus', 'message'])

# 9. Webhook
print('\n## 9 Webhook')
print('   không xác thực   :', webhook({'_id': aha_id, 'status': 'IN PROCESS'}))
print('   ?hash=secret      :', webhook({'_id': aha_id, 'status': 'IN PROCESS'}, f'?hash={secret}'))
print('   header apikey     :', webhook({'_id': f'{aha_id}-1', 'status': 'COMPLETED',
                                          'path': [{}, {'status': 'FAILED'}]}, headers={'apikey': secret}))
print('   events:', json.dumps(events(oid), ensure_ascii=False)[:1500])

# 10. Token hết hạn / bị thu hồi → 401 → lấy lại
before = token_calls()
mock('/__rotate')
st, js, _ = api.call('POST', f'/api/pos/shipping/shipments/{oid}/sync-tracking')
show('10a Đồng bộ sau khi AhaMove thu hồi token', st, js, ['success', 'statusName', 'message'])
mid = token_calls()
st, js, _ = api.call('POST', f'/api/pos/shipping/shipments/{oid}/sync-tracking')
show('10b Đồng bộ lần kế', st, js, ['success', 'statusName', 'message'])
after = token_calls()
print(f'   token calls: trước={before} sau 10a={mid} sau 10b={after} '
      f'(10b > 10a nghĩa là token mới KHÔNG được lưu)')

# 11. Hủy vận đơn đơn B, rồi tạo lại
oid2, _ = new_delivery_order('B')
st, js, _ = api.call('POST', '/api/pos/shipping/shipments', {**create, 'orderId': oid2})
d2 = show('11a Tạo vận đơn đơn B', st, js, ['success', 'trackingCode', 'message'])
st, js, _ = api.call('POST', f'/api/pos/shipping/shipments/{oid2}/cancel', {'note': 'QA hủy thử'})
show('11b Hủy vận đơn', st, js, ['success', 'message'])
st, js, _ = api.call('POST', '/api/pos/shipping/shipments', {**create, 'orderId': oid2})
show('11c Tạo lại sau hủy', st, js, ['success', 'trackingCode', 'message'])
aha_id2 = (js.get('data') or {}).get('trackingCode')
mock(f'/__state/{aha_id2}', {'status': 'IN PROCESS'})
st, js, _ = api.call('POST', f'/api/pos/shipping/shipments/{oid2}/cancel', {'note': 'QA hủy khi đang giao'})
show('11d Hủy khi đang giao (AhaMove từ chối)', st, js, ['success', 'message'])

print('\nORDER_IDS', oid, oid2)
print('\n## Các lời gọi tới AhaMove giả:')
for c in mock_calls():
    print(f"   {c['t']} {c['method']} {c['path']} -> {c['status']}")
