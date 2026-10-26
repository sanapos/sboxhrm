"""Tải đồng thời: N người dùng cùng thao tác thường ngày trên cửa hàng nhiều dữ liệu (đọc — không ghi dữ liệu).

  python -I scripts/qa/qa_load_concurrent.py [Retail] [users=30] [seconds=40] [think=2.5]

In: số request/giây, p50 / p95 / max (ms), số lỗi theo HTTP.
"""
import datetime as dt
import os
import random
import statistics
import sys
import threading
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_print_agent as p  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
ind = sys.argv[1] if len(sys.argv) > 1 else 'Retail'
users = int(sys.argv[2]) if len(sys.argv) > 2 else 30
seconds = int(sys.argv[3]) if len(sys.argv) > 3 else 40
# Nghỉ giữa 2 thao tác (giây) — mô phỏng thu ngân thật. 0 = dồn dập (sẽ chạm giới hạn 1000 request/phút/tài khoản
# của API: mọi luồng dùng chung 1 tài khoản nên request bị xếp hàng ~20 giây — không phải máy chủ chậm).
think = float(sys.argv[4]) if len(sys.argv) > 4 else 2.5
api = p.api(ind)
d = dt.date.today().isoformat()
q = urllib.parse.quote

ACTIONS = [
    (5, '/api/pos/sales/products?page=1&pageSize=100'),
    (5, lambda: f'/api/pos/sales/lookup?code=893{random.randint(1, 50000):010d}'),
    (3, lambda: f'/api/pos/products?page=1&pageSize=50&search={q("hàng tải " + str(random.randint(1, 50000)))}'),
    (3, lambda: f'/api/pos/customers?page=1&pageSize=50&search=09{random.randint(1, 30000):08d}'),
    (3, '/api/pos/sales?page=1&pageSize=50'),
    (2, lambda: f'/api/pos/sales?page=1&pageSize=50&search=LT{random.randint(1, 200000):07d}'),
    (1, f'/api/pos/reports/sales/summary?from={d}&to={d}'),
    (1, f'/api/pos/reports/analysis/overview?from={d}&to={d}'),
    (1, f'/api/pos/reports/end-of-day?date={d}'),
]
weighted = [a for w, a in ACTIONS for _ in range(w)]

lat, errors, lock = [], {}, threading.Lock()
by_kind = {}
slow = []
stop = time.time() + seconds


def worker():
    while time.time() < stop:
        if think > 0:
            time.sleep(random.uniform(think * 0.4, think * 1.6))
        a = random.choice(weighted)
        path = a() if callable(a) else a
        started = time.time()
        st, _, ms = api.call('GET', path, raw=True)
        kind = path.split('?')[0]
        if ms > 5000:
            with lock:
                slow.append((started - t0, ms, kind))
        with lock:
            lat.append(ms)
            by_kind.setdefault(kind, []).append(ms)
            if st != 200:
                errors[st] = errors.get(st, 0) + 1


t0 = time.time()
threads = [threading.Thread(target=worker) for _ in range(users)]
for t in threads:
    t.start()
for t in threads:
    t.join()
el = time.time() - t0
lat.sort()
pct = lambda x: lat[min(len(lat) - 1, int(len(lat) * x))]
print(f'{users} người dùng · {el:.0f}s · {len(lat)} request · {len(lat) / el:.1f} req/s')
print(f'p50 {pct(0.5):.0f} ms · p95 {pct(0.95):.0f} ms · max {lat[-1]:.0f} ms · trung bình {statistics.mean(lat):.0f} ms')
print('lỗi:', errors or 'không')
if slow:
    slow.sort()
    print(f'chậm >5s: {len(slow)} request, bắt đầu từ giây {slow[0][0]:.1f} tới {slow[-1][0]:.1f}')
for kind, xs in sorted(by_kind.items(), key=lambda kv: -max(kv[1])):
    xs.sort()
    print(f'  {kind:<42} n={len(xs):>4} p50={xs[len(xs) // 2]:>6.0f} p95={xs[int(len(xs) * 0.95)]:>6.0f} max={xs[-1]:>6.0f}')
