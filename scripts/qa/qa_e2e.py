"""E2E nghiệp vụ qua API trên server test LOCAL (scripts/run-qa-api.ps1, http://localhost:7070).

Chạy:  python -I scripts/qa/qa_e2e.py [--base http://localhost:7070] [--only register,login,...]
Tài khoản test sinh ngẫu nhiên, lưu ở scripts/qa/.qa-accounts.json (gitignore) để lần sau dùng lại.
KHÔNG trỏ vào server production.
"""
import argparse
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ACCOUNTS = os.path.join(HERE, '.qa-accounts.json')

INDUSTRIES = ['Retail', 'Salon', 'RoomHourly', 'Restaurant', 'Gym', 'Hotel']
# Ngành bán theo bàn/phòng bắt buộc: không cho lưu đơn quầy («Cần chọn bàn/phòng trước khi lưu đơn»).
ROOM_REQUIRED = {'RoomHourly', 'Hotel'}
# Ngành không có sơ đồ bàn/phòng: mở bàn phải bị từ chối.
NO_FLOOR = {'Retail', 'Gym'}

RESULTS = []  # (step, store, ok, detail, ms)


class Api:
    def __init__(self, base, token=None):
        self.base = base.rstrip('/')
        self.token = token

    def call(self, method, path, body=None, raw=False):
        data = None if body is None else json.dumps(body).encode('utf-8')
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header('Content-Type', 'application/json')
        if self.token:
            req.add_header('Authorization', 'Bearer ' + self.token)
        t0 = time.perf_counter()
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                payload = r.read()
                status = r.status
        except urllib.error.HTTPError as e:
            payload = e.read()
            status = e.code
        ms = (time.perf_counter() - t0) * 1000
        if raw:
            return status, payload, ms
        try:
            js = json.loads(payload.decode('utf-8')) if payload else None
        except ValueError:
            js = {'_raw': payload[:300].decode('utf-8', 'replace')}
        return status, js, ms


def record(step, store, ok, detail='', ms=0.0):
    RESULTS.append((step, store, ok, detail, ms))
    mark = 'PASS' if ok else 'FAIL'
    print(f'[{mark}] {step:<28} {store:<11} {ms:7.0f}ms  {detail}')


def ok_resp(status, js):
    return 200 <= status < 300 and isinstance(js, dict) and js.get('isSuccess', True) is not False


def msg(js):
    if isinstance(js, dict):
        return str(js.get('message') or js.get('title') or js.get('errors') or js)[:200]
    return str(js)[:200]


def load_accounts():
    if os.path.exists(ACCOUNTS):
        with open(ACCOUNTS, encoding='utf-8-sig') as f:
            return json.load(f)
    return {}


def save_accounts(acc):
    with open(ACCOUNTS, 'w', encoding='utf-8') as f:
        json.dump(acc, f, ensure_ascii=False, indent=2)


def dev_seed_superadmin():
    """Server Development tự seed Super Admin (ZKTecoDbInitializer.SeedSuperAdminAsync) — lấy email/mật khẩu từ đó."""
    import re
    src = os.path.join(HERE, '..', '..', 'src', 'ZKTecoADMS.Infrastructure', 'ZKTecoDbInitializer.cs')
    with open(src, encoding='utf-8') as f:
        body = f.read().split('private async Task SeedSuperAdminAsync()', 1)[1].split('private async Task', 1)[0]
    email = re.search(r'const string email = "([^"]+)"', body)
    pw = re.search(r'CreateAsync\(user, "([^"]+)"\)', body)
    if not (email and pw):
        return None
    return {'email': email.group(1), 'password': pw.group(1)}


def step_superadmin(base, acc):
    """Cài mới: tạo Super Admin đầu tiên + gói «Dùng thử» đủ chức năng (cửa hàng không chọn gói sẽ dùng gói này)."""
    sa = acc.get('_superadmin')
    if not sa:
        sa = {'email': f'qa.superadmin.{secrets.token_hex(3)}@sbox-qa.test',
              'password': 'Qa!' + secrets.token_urlsafe(12), 'fullName': 'QA Super Admin'}
        st, js, ms = Api(base).call('POST', '/api/Auth/Setup', sa)
        good = ok_resp(st, js)
        if not good:
            sa = dev_seed_superadmin()
            good = sa is not None
        record('superadmin.setup', '-', good, f'HTTP {st} {"tạo mới" if st == 200 else "dùng tài khoản seed dev"}', ms)
        if not good:
            return None
        acc['_superadmin'] = sa
        save_accounts(acc)
    st, js, ms = Api(base).call('POST', '/api/auth/AdminLogin', {'userName': sa['email'], 'password': sa['password']})
    d = data(js) if ok_resp(st, js) else None
    token = (d or {}).get('accessToken') or (d or {}).get('token')
    record('superadmin.login', '-', bool(token), f'HTTP {st} {"" if token else msg(js)}', ms)
    if not token:
        return None
    api = Api(base, token)
    st, js, ms = api.call('GET', '/api/system-admin/service-packages')
    if any(p.get('name') == 'Dùng thử' for p in (data(js) or [])):
        return token
    st, js, ms = api.call('GET', '/api/system-admin/service-packages/available-modules')
    modules = [m.get('code') or m.get('moduleCode') for m in (data(js) or [])]
    modules = [m for m in modules if m]
    record('superadmin.modules', '-', len(modules) > 20, f'{len(modules)} chức năng', ms)
    body = {'name': 'Dùng thử', 'description': 'QA', 'defaultDurationDays': 30, 'maxUsers': 50,
            'maxDevices': 10, 'allowedModules': modules, 'maxBranches': 5}
    st, js, ms = api.call('POST', '/api/system-admin/service-packages', body)
    record('superadmin.package', '-', ok_resp(st, js), f'HTTP {st} {"" if ok_resp(st, js) else msg(js)}', ms)
    return token


def step_register(base, acc):
    run = secrets.token_hex(3)
    for ind in INDUSTRIES:
        if ind in acc:
            continue
        code = f'qa{ind.lower()[:6]}{run}'
        a = {
            'storeName': f'QA {ind} {run}',
            'email': f'qa.{ind.lower()}.{run}@sbox-qa.test',
            'password': 'Qa!' + secrets.token_urlsafe(9),
            'phoneNumber': f'09{secrets.randbelow(10**8):08d}',
            'province': 'Đà Nẵng',
            'storeCode': code,
            'sellProfile': ind,
        }
        st, js, ms = Api(base).call('POST', '/api/auth/register', a)
        good = ok_resp(st, js)
        record('register', ind, good, f'HTTP {st} {"" if good else msg(js)}', ms)
        if good:
            acc[ind] = a
    save_accounts(acc)


def login(base, a):
    body = {'storeCode': a['storeCode'], 'userName': a['email'], 'password': a['password']}
    st, js, ms = Api(base).call('POST', '/api/auth/login', body)
    token = None
    if ok_resp(st, js):
        d = js.get('data') or {}
        token = d.get('accessToken') or d.get('token')
    return st, js, ms, token


def step_login(base, acc, tokens):
    for ind, a in acc.items():
        if ind.startswith('_'):
            continue
        st, js, ms, token = login(base, a)
        record('login', ind, bool(token), f'HTTP {st} {"" if token else msg(js)}', ms)
        if token:
            tokens[ind] = token


def data(js):
    return js.get('data') if isinstance(js, dict) else None


def step_catalog(base, tokens, ctx):
    """Nhân viên, sản phẩm (hàng + dịch vụ), khách hàng cho từng cửa hàng."""
    for ind, tk in tokens.items():
        api = Api(base, tk)
        c = ctx.setdefault(ind, {})
        emp = {'employeeCode': 'NV' + secrets.token_hex(2).upper(), 'firstName': 'Thu', 'lastName': 'Ngân QA',
               'phoneNumber': f'09{secrets.randbelow(10**8):08d}', 'gender': 'Female',
               'joinDate': time.strftime('%Y-%m-%dT00:00:00')}
        st, js, ms = api.call('POST', '/api/employees', emp)
        record('employee.create', ind, ok_resp(st, js), f'HTTP {st} {"" if ok_resp(st, js) else msg(js)}', ms)
        c['employeeId'] = data(js) if ok_resp(st, js) else None

        prods = [
            ('Hàng QA A', 'Goods', 50000, 30000, 100),
            ('Hàng QA B', 'Goods', 30000, 18000, 100),
            ('Dịch vụ QA', 'Service', 200000, 0, 0),
            ('Giờ phòng QA', 'Service', 120000, 0, 0),  # tính theo giờ — gắn vào bàn/phòng
        ]
        c['products'] = []
        for name, ptype, price, cost, qty in prods:
            body = {'name': name, 'productType': ptype, 'basePrice': price, 'costPrice': cost,
                    'onHandQty': qty, 'vatRate': 0, 'baseUnitName': 'Cái' if ptype == 'Goods' else 'Lần'}
            if name.startswith('Giờ'):
                body.update({'serviceBillingMode': 'PerHour', 'baseUnitName': 'Giờ'})
            st, js, ms = api.call('POST', '/api/pos/products', body)
            good = ok_resp(st, js) and isinstance(data(js), dict)
            record(f'product.create {ptype}', ind, good, f'HTTP {st} {"" if good else msg(js)}', ms)
            if good:
                d = data(js)
                c['products'].append({'id': d['id'], 'price': price, 'cost': cost, 'type': ptype,
                                      'onHand': d.get('onHandQty')})

        st, js, ms = api.call('POST', '/api/pos/customers',
                              {'name': 'Khách QA', 'phone': f'09{secrets.randbelow(10**8):08d}'})
        good = ok_resp(st, js) and isinstance(data(js), dict)
        record('customer.create', ind, good, f'HTTP {st} {"" if good else msg(js)}', ms)
        c['customerId'] = data(js)['id'] if good else None


def step_quote(base, tokens, ctx):
    for ind, tk in tokens.items():
        c = ctx.get(ind) or {}
        if len(c.get('products', [])) < 2:
            continue
        api = Api(base, tk)
        a, b = c['products'][0], c['products'][1]
        body = {'customerId': c.get('customerId'), 'customerName': 'Khách QA',
                'lines': [{'productId': a['id'], 'productName': 'Hàng QA A', 'qty': 3, 'unitPrice': a['price']},
                          {'productId': b['id'], 'productName': 'Hàng QA B', 'qty': 2, 'unitPrice': b['price'],
                           'discountAmount': 5000}],
                'discount': 10000, 'vatMode': 'added', 'vatPercent': 8}
        st, js, ms = api.call('POST', '/api/pos/quotes', body)
        good = ok_resp(st, js) and isinstance(data(js), dict)
        record('quote.create', ind, good, f'HTTP {st} {"" if good else msg(js)}', ms)
        if not good:
            continue
        q = data(js)
        # (3×50.000) + (2×30.000 − 5.000) = 205.000; − 10.000 = 195.000; VAT 8% = 15.600 → 210.600
        exp_total = 210600
        got = q.get('total')
        record('quote.total', ind, got is not None and abs(float(got) - exp_total) < 1,
               f'kỳ vọng {exp_total}, nhận {got} (VAT {q.get("vatAmount")})')
        st, js, ms = api.call('POST', f"/api/pos/quotes/{q['id']}/preview", {'kind': 'Quote'})
        html = json.dumps(data(js) or {}, ensure_ascii=False)
        record('quote.preview', ind, ok_resp(st, js) and '210.600' in html,
               f'HTTP {st} {len(html)}B {"có" if "210.600" in html else "THIẾU"} tổng 210.600', ms)


def sale(api, lines, discount, paid, method='Cash', payments=None, customer_id=None):
    body = {'lines': lines, 'discount': discount, 'paidAmount': paid, 'paymentMethod': method,
            'customerName': None, 'customerId': customer_id, 'note': 'QA', 'complete': True,
            'clientRequestId': secrets.token_hex(8)}
    if payments:
        body['payments'] = payments
    return api.call('POST', '/api/pos/sales', body)


def revenue_today(api):
    today = time.strftime('%Y-%m-%d')
    st, js, ms = api.call('GET', f'/api/pos/reports/sales/summary?from={today}&to={today}')
    return float((data(js) or {}).get('totalRevenue') or 0) if ok_resp(st, js) else 0.0


def step_sales(base, tokens, ctx):
    for ind, tk in tokens.items():
        c = ctx.get(ind) or {}
        c['expected_revenue'] = 0
        c['revenue_before'] = revenue_today(Api(base, tk))
        if len(c.get('products', [])) < 2 or ind in ROOM_REQUIRED:
            continue
        api = Api(base, tk)
        a, b = c['products'][0], c['products'][1]
        # 1) Tiền mặt + chiết khấu đơn: 2×50.000 + 1×30.000 − 10.000 = 120.000
        lines = [{'productId': a['id'], 'qty': 2, 'unitPrice': a['price']},
                 {'productId': b['id'], 'qty': 1, 'unitPrice': b['price']}]
        st, js, ms = sale(api, lines, 10000, 120000)
        good = ok_resp(st, js) and isinstance(data(js), dict)
        d = data(js) if good else {}
        total = d.get('total') if good else None
        record('sale.cash+discount', ind, good and abs(float(total or -1) - 120000) < 1,
               f'HTTP {st} total={total} {"" if good else msg(js)}', ms)
        if good:
            c['sale1'] = d
            c['expected_revenue'] += 120000
        # 2) Nhiều hình thức: 3×30.000 = 90.000 = 50.000 tiền mặt + 40.000 chuyển khoản
        lines = [{'productId': b['id'], 'qty': 3, 'unitPrice': b['price']}]
        pays = [{'amount': 50000, 'paymentMethod': 'Cash'}, {'amount': 40000, 'paymentMethod': 'BankTransfer'}]
        st, js, ms = sale(api, lines, 0, 90000, 'Mixed', pays)
        good = ok_resp(st, js)
        record('sale.split-payment', ind, good, f'HTTP {st} {"" if good else msg(js)}', ms)
        if good:
            c['expected_revenue'] += 90000
        # 3) Ghi nợ khách: 1×50.000, trả 20.000 → nợ 30.000
        if c.get('customerId'):
            lines = [{'productId': a['id'], 'qty': 1, 'unitPrice': a['price']}]
            st, js, ms = sale(api, lines, 0, 20000, customer_id=c['customerId'])
            good = ok_resp(st, js)
            record('sale.partial-debt', ind, good, f'HTTP {st} {"" if good else msg(js)}', ms)
            if good:
                c['expected_revenue'] += 50000
                st2, js2, ms2 = api.call('GET', f"/api/pos/customers/{c['customerId']}/debt-summary")
                dd = data(js2) or {}
                debt = dd.get('currentDebt', dd.get('debt', dd.get('totalDebt')))
                record('customer.debt=30000', ind, debt is not None and abs(float(debt) - 30000) < 1,
                       f'nợ={debt}', ms2)
        # 4) Đơn để hủy: 1×30.000 rồi hủy → không tính doanh thu, trả lại tồn
        lines = [{'productId': b['id'], 'qty': 1, 'unitPrice': b['price']}]
        st, js, ms = sale(api, lines, 0, 30000)
        if ok_resp(st, js):
            oid = data(js)['id']
            st2, js2, ms2 = api.call('POST', f'/api/pos/sales/{oid}/cancel', {'reason': 'QA hủy thử'})
            record('sale.cancel', ind, ok_resp(st2, js2), f'HTTP {st2} {"" if ok_resp(st2, js2) else msg(js2)}', ms2)
        else:
            record('sale.cancel(create)', ind, False, f'HTTP {st} {msg(js)}', ms)
        # Tồn kho: A bán 2+1 = 3 → 97; B bán 1+3 (+1 hủy trả lại) = 4 → 96
        st, js, ms = api.call('GET', f"/api/pos/products/{a['id']}")
        oa = (data(js) or {}).get('onHandQty')
        st, js, ms = api.call('GET', f"/api/pos/products/{b['id']}")
        ob = (data(js) or {}).get('onHandQty')
        record('stock.after-sales', ind, oa is not None and ob is not None and float(oa) == 97 and float(ob) == 96,
               f'A={oa} (kỳ vọng 97) B={ob} (kỳ vọng 96)')


def step_floor(base, tokens, ctx):
    """Ngành có bàn/phòng: mở phiên → bán kèm phòng (dịch vụ tính giờ + hàng) → phòng trống lại."""
    for ind, tk in tokens.items():
        c = ctx.get(ind) or {}
        api = Api(base, tk)
        st, js, ms = api.call('GET', '/api/pos/service-resources')
        d = data(js)
        res = d if isinstance(d, list) else (d or {}).get('items') if isinstance(d, dict) else None
        if not ok_resp(st, js):
            record('floor.resources', ind, False, f'HTTP {st} {msg(js)}', ms)
            continue
        record('floor.resources', ind, True, f'{len(res or [])} bàn/phòng có sẵn', ms)
        if len(c.get('products', [])) < 4:
            continue
        if not res:
            st, js, ms = api.call('POST', '/api/pos/service-areas', {'name': 'Khu QA', 'code': 'QA'})
            area = data(js) if ok_resp(st, js) else None
            record('floor.area.create', ind, bool(area), f'HTTP {st} {"" if area else msg(js)}', ms)
            if not area:
                continue
            res = []
            for i in (1, 2):
                st, js, ms = api.call('POST', '/api/pos/service-resources',
                                      {'areaId': area['id'], 'code': f'P{i:02d}', 'name': f'Phòng QA {i}',
                                       'capacity': 4, 'defaultHourlyRate': 120000,
                                       'defaultServiceProductId': c['products'][3]['id']})
                d = data(js) if ok_resp(st, js) else None
                if isinstance(d, dict) and 'resource' in d:
                    d = d['resource']
                record('floor.resource.create', ind, bool(d), f'HTTP {st} {"" if d else msg(js)}', ms)
                if d:
                    res.append(d)
            if not res:
                continue
        r = res[0]
        st, js, ms = api.call('POST', '/api/pos/resource-sessions/open',
                              {'resourceId': r['id'], 'guestCount': 2, 'deviceId': 'qa-script', 'deviceName': 'QA'})
        good = ok_resp(st, js)
        sess = data(js) or {}
        if isinstance(sess, dict) and 'session' in sess:
            sess = sess['session']
        if ind in NO_FLOOR:
            record('floor.open bị chặn (đúng)', ind, st == 400 and 'không bật bàn' in msg(js), f'HTTP {st} {msg(js)}', ms)
            continue
        record('floor.open', ind, good, f'HTTP {st} {r.get("name")} {"" if good else msg(js)}', ms)
        if not good:
            continue
        a, timed = c['products'][0], c['products'][3]
        lines = [{'productId': a['id'], 'qty': 1, 'unitPrice': a['price']},
                 {'productId': timed['id'], 'qty': 1, 'unitPrice': timed['price']}]
        # Luồng app: phiên phòng đã có đơn nháp → ghi món vào đơn đó rồi thanh toán (POST /sales = tách hóa đơn).
        order_id = sess.get('saleOrderId')
        body = {'lines': lines, 'discount': 0, 'paidAmount': 52000, 'paymentMethod': 'Cash', 'complete': True,
                'serviceResourceId': r['id'], 'resourceSessionId': sess.get('id'),
                'deviceId': 'qa-script', 'deviceName': 'QA'}
        st, js, ms = api.call('PUT', f'/api/pos/sales/{order_id}', body)
        good = ok_resp(st, js) and (data(js) or {}).get('status') == 'Completed'
        record('floor.checkout', ind, good, f'HTTP {st} total={(data(js) or {}).get("total")} {"" if good else msg(js)}', ms)
        if good:
            c['expected_revenue'] = c.get('expected_revenue', 0) + float((data(js) or {}).get('total') or 0)
        st, js, ms = api.call('GET', '/api/pos/resource-sessions/open')
        still = [s for s in (data(js) or []) if isinstance(s, dict) and s.get('resourceId') == r['id']] \
            if isinstance(data(js), list) else None
        record('floor.freed-after-pay', ind, still == [], f'phiên còn mở: {still}', ms)


def step_reports(base, tokens, ctx):
    today = time.strftime('%Y-%m-%d')
    for ind, tk in tokens.items():
        c = ctx.get(ind) or {}
        if 'expected_revenue' not in c:
            continue
        api = Api(base, tk)
        st, js, ms = api.call('GET', f'/api/pos/reports/sales/summary?from={today}&to={today}')
        d = data(js) if ok_resp(st, js) else None
        rev = None
        if isinstance(d, dict):
            for k in ('netRevenue', 'revenue', 'totalRevenue', 'totalAmount', 'grossRevenue'):
                if d.get(k) is not None:
                    rev = d[k]
                    break
        exp = c['expected_revenue'] + c.get('revenue_before', 0)
        record('report.sales.summary', ind, rev is not None and abs(float(rev) - exp) < 1,
               f'kỳ vọng {exp}, nhận {rev} keys={list(d.keys())[:12] if isinstance(d, dict) else d}', ms)
        st, js, ms = api.call('GET', f'/api/pos/reports/end-of-day?date={today}')
        record('report.end-of-day', ind, ok_resp(st, js), f'HTTP {st} {"" if ok_resp(st, js) else msg(js)}', ms)
        for path in ('/api/pos/reports/goods/summary', '/api/pos/reports/profit/by-product',
                     '/api/pos/reports/cashbook/summary', '/api/pos/reports/pnl/summary',
                     '/api/pos/reports/analysis/overview', '/api/pos/reports/stock/summary'):
            st, js, ms = api.call('GET', f'{path}?from={today}&to={today}')
            record('report ' + path.split('/reports/')[1], ind, ok_resp(st, js),
                   f'HTTP {st} {"" if ok_resp(st, js) else msg(js)}', ms)
        for path in ('/api/pos/reports/sales/export/excel', '/api/pos/products/export/excel',
                     '/api/employees/export/excel'):
            st, raw, ms = api.call('GET', f'{path}?from={today}&to={today}', raw=True)
            record('export ' + path, ind, st == 200 and raw[:2] == b'PK', f'HTTP {st} {len(raw)}B', ms)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser()
    # 127.0.0.1 chứ không phải localhost: Windows thử IPv6 trước → mỗi request trễ ~2 giây.
    ap.add_argument('--base', default='http://127.0.0.1:7070')
    ap.add_argument('--reuse', action='store_true', help='dùng lại cửa hàng của lần chạy trước')
    args = ap.parse_args()
    if 'sbox.sana.vn' in args.base or 'sboxpos.com' in args.base or 'sboxhrm.com' in args.base:
        sys.exit('Từ chối: chỉ chạy trên server test local.')
    acc = load_accounts()
    if not args.reuse:
        # Mỗi lần chạy dùng cửa hàng mới: số liệu báo cáo/tồn kho/phòng không lẫn lần trước.
        acc = {k: v for k, v in acc.items() if k.startswith('_')}
    tokens = {}
    step_superadmin(args.base, acc)
    step_register(args.base, acc)
    step_login(args.base, acc, tokens)
    ctx = {}
    step_catalog(args.base, tokens, ctx)
    step_quote(args.base, tokens, ctx)
    step_sales(args.base, tokens, ctx)
    step_floor(args.base, tokens, ctx)
    step_reports(args.base, tokens, ctx)
    fails = [r for r in RESULTS if not r[2]]
    print(f'\nTổng: {len(RESULTS)} bước, {len(fails)} lỗi')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
