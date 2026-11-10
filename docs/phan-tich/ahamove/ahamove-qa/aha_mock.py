"""Máy chủ giả AhaMove Partner API v3 (chỉ để QA local) — ghi mọi request vào aha_mock.jsonl.

Hành vi theo docs developers.ahamove.com:
  POST /v3/accounts/token    {mobile, api_key} → {token, refresh_token}
  POST /v3/accounts          đăng ký user mới
  POST /v3/orders/estimates  → [{service_id, data:{total_price, duration…}}]
  POST /v3/orders            → {order_id, status, shared_link, order:{…}}
  GET  /v3/orders/{id}       → chi tiết đơn (status theo STATE[id])
  DELETE /v3/orders/{id}     → {} hoặc 406 INVALID_ORDER_STATUS
Điều khiển: POST /__rotate (vô hiệu token cũ), POST /__state/{id} {"status":…,"sub_status":…,"path_status":…}
"""
import base64
import json
import os
import random
import string
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'aha_mock.jsonl')
API_KEY = 'qa-mock-api-key'
VALID_TOKENS = set()
ORDERS = {}


def b64(d):
    return base64.urlsafe_b64encode(json.dumps(d).encode()).decode().rstrip('=')


def new_token(mobile):
    t = b64({'alg': 'HS256'}) + '.' + b64({'exp': int(time.time()) + 3600, 'sub': mobile,
                                          'n': random.randint(0, 10**9)}) + '.c2ln'
    VALID_TOKENS.add(t)
    return t


class H(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'  # keep-alive như AhaMove thật (HTTP/1.0 đóng socket → .NET dùng lại kết nối chết)

    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        raw = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)
        return code, obj

    def _body(self):
        n = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(n).decode('utf-8') if n else ''
        try:
            return json.loads(raw) if raw else None
        except Exception:
            return raw

    def _authed(self):
        a = (self.headers.get('Authorization') or '').strip()
        return a.startswith('Bearer ') and a[7:].strip() in VALID_TOKENS

    def _handle(self, method):
        body = self._body()
        path = self.path.split('?')[0]
        res = self._route(method, path, body)
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(json.dumps({'t': time.strftime('%H:%M:%S'), 'method': method, 'path': path,
                                'auth': (self.headers.get('Authorization') or '')[:20],
                                'body': body, 'status': res[0], 'resp': res[1]},
                               ensure_ascii=False) + '\n')

    def _route(self, method, path, body):
        if method == 'POST' and path == '/__rotate':
            VALID_TOKENS.clear()
            return self._send(200, {'ok': True})
        if method == 'POST' and path.startswith('/__state/'):
            oid = path.split('/')[-1]
            ORDERS.setdefault(oid, {}).update(body or {})
            return self._send(200, {'ok': True, 'order': ORDERS[oid]})
        if method == 'POST' and path == '/v3/accounts/token':
            if not isinstance(body, dict) or body.get('api_key') != API_KEY:
                return self._send(401, {'title': 'INVALID_API_KEY', 'description': 'API key is invalid'})
            return self._send(200, {'token': new_token(body.get('mobile')), 'refresh_token': 'r1'})
        if method == 'POST' and path == '/v3/accounts':
            return self._send(409, {'title': 'ACCOUNT_EXISTED', 'description': 'Account existed'})
        if not self._authed():
            return self._send(401, {'title': 'NOT_AUTHORIZED', 'description': 'Token is invalid or expired'})
        if method == 'POST' and path == '/v3/orders/estimates':
            grp = ((body or {}).get('group_services') or [{}])[0].get('_id', 'BIKE')
            path_ = (body or {}).get('path') or []
            if len(path_) < 2 or not path_[1].get('address'):
                return self._send(400, {'title': 'INVALID_PATH', 'description': 'path is invalid'})
            return self._send(200, [{'service_id': f'DAD-{grp}', 'data': {
                'distance': 3.2, 'duration': 1500, 'distance_fee': 23000, 'request_fee': 0,
                'stop_fee': 0, 'vat_fee': 0, 'discount': 0, 'total_fee': 33000, 'requests': [],
                'total_price': 33000}}])
        if method == 'POST' and path == '/v3/orders':
            b = body or {}
            if not (b.get('service_id') or b.get('group_service_id')):
                return self._send(400, {'title': 'INVALID_SERVICE', 'description': 'service_id is required'})
            oid = '26' + ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
            ORDERS[oid] = {'status': 'ASSIGNING', 'sub_status': None, 'path_status': None, 'req': b}
            return self._send(200, {'order_id': oid, 'status': 'ASSIGNING',
                                    'shared_link': f'https://cloudjetstg.ahamove.com/share-order/{oid}',
                                    'order': {'_id': oid, 'currency': 'VND', 'total_pay': 33000,
                                              'total_fee': 33000, 'total_price': 33000,
                                              'service_id': b.get('service_id') or b.get('group_service_id'),
                                              'status': 'ASSIGNING'}})
        if path.startswith('/v3/orders/'):
            oid = path.split('/')[-1]
            o = ORDERS.get(oid)
            if o is None:
                return self._send(404, {'title': 'ORDER_NOT_FOUND', 'description': 'Order not found'})
            if method == 'GET':
                now = int(time.time())
                return self._send(200, {'_id': oid, 'status': o['status'], 'sub_status': o.get('sub_status'),
                                        'create_time': now - 600, 'accept_time': now - 300,
                                        'shared_link': f'https://cloudjetstg.ahamove.com/share-order/{oid}',
                                        'supplier_name': 'Tài xế QA',
                                        'path': [{'address': 'Lấy hàng'},
                                                 {'address': 'Giao hàng', 'status': o.get('path_status')}]})
            if method == 'DELETE':
                if o['status'] in ('IN PROCESS', 'COMPLETED'):
                    return self._send(406, {'title': 'INVALID_ORDER_STATUS',
                                            'description': 'Order status is not cancellable'})
                o['status'] = 'CANCELLED'
                return self._send(200, {})
        return self._send(404, {'title': 'NOT_FOUND', 'description': path})

    def do_GET(self):
        self._handle('GET')

    def do_POST(self):
        self._handle('POST')

    def do_DELETE(self):
        self._handle('DELETE')


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 7099
    print(f'AhaMove mock on 127.0.0.1:{port}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
