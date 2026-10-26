"""Đo tốc độ API khi cửa hàng có nhiều dữ liệu (chạy sau khi nạp dữ liệu tải lớn vào QA Retail).

  python -I scripts/qa/qa_load_measure.py [Retail] [out.json]

In từng endpoint: HTTP, thời gian (ms, lấy lần nhanh nhất / chậm nhất trong 2 lần gọi), kích thước phản hồi.
Mỗi endpoint gọi 2 lần (lần đầu có thể chậm do cache / JIT).
"""
import datetime as dt
import json
import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_print_agent as p  # noqa: E402  (dùng lại token cache)

sys.stdout.reconfigure(encoding='utf-8')
ind = sys.argv[1] if len(sys.argv) > 1 else 'Retail'
out = sys.argv[2] if len(sys.argv) > 2 else None
api = p.api(ind)

today = dt.date.today()
d = today.isoformat()
month = today.replace(day=1).isoformat()
year = (today - dt.timedelta(days=365)).isoformat()
q = urllib.parse.quote

ENDPOINTS = [
    ('Đơn hàng — trang 1', f'/api/pos/sales?page=1&pageSize=50'),
    ('Đơn hàng — tháng này', f'/api/pos/sales?page=1&pageSize=50&from={month}&to={d}'),
    ('Đơn hàng — 1 năm', f'/api/pos/sales?page=1&pageSize=50&from={year}&to={d}'),
    ('Đơn hàng — tìm mã', f'/api/pos/sales?page=1&pageSize=50&search=LT0123456'),
    ('Đơn hàng — trang 2000', f'/api/pos/sales?page=2000&pageSize=50'),
    ('Hàng hóa — trang 1', '/api/pos/products?page=1&pageSize=50'),
    ('Hàng hóa — tìm tên', f'/api/pos/products?page=1&pageSize=50&search={q("hàng tải 4321")}'),
    ('Hàng hóa — tìm mã vạch', '/api/pos/products?page=1&pageSize=50&search=8930000043210'),
    ('Bán hàng — quét mã vạch', '/api/pos/sales/lookup?code=8930000043210'),
    ('Bán hàng — quét mã hàng', '/api/pos/sales/lookup?code=LT043210'),
    ('Bán hàng — danh mục', '/api/pos/sales/products'),
    ('Bán hàng — tìm', f'/api/pos/sales/products?search={q("áo")}'),
    ('Khách hàng — trang 1', '/api/pos/customers?page=1&pageSize=50'),
    ('Khách hàng — tìm SĐT', '/api/pos/customers?page=1&pageSize=50&search=0900012345'),
    ('Người bán', '/api/pos/sales/sellers'),
    ('BC bán hàng — hôm nay', f'/api/pos/reports/sales/summary?from={d}&to={d}'),
    ('BC bán hàng — 1 năm', f'/api/pos/reports/sales/summary?from={year}&to={d}'),
    ('BC đơn — 1 năm', f'/api/pos/reports/sales/orders?from={year}&to={d}'),
    ('Tổng quan — hôm nay', f'/api/pos/reports/analysis/overview?from={d}&to={d}'),
    ('Tổng quan — 1 năm', f'/api/pos/reports/analysis/overview?from={year}&to={d}'),
    ('Cuối ngày', f'/api/pos/reports/end-of-day?date={d}'),
    ('Lãi theo hàng — 1 năm', f'/api/pos/reports/profit/by-product?from={year}&to={d}'),
    ('Hàng bán — 1 năm', f'/api/pos/reports/goods/summary?from={year}&to={d}'),
    ('KH mua — 1 năm', f'/api/pos/reports/customers/sales?from={year}&to={d}'),
    ('Sổ quỹ — tháng', f'/api/pos/reports/cashbook/summary?from={month}&to={d}'),
    ('Lãi lỗ — 1 năm', f'/api/pos/reports/pnl/summary?from={year}&to={d}'),
    ('Tồn kho — tổng', f'/api/pos/reports/stock/summary?from={month}&to={d}'),
    ('Tồn kho — sức khỏe', '/api/pos/reports/stock/health'),
    ('Xuất Excel đơn — tháng', f'/api/pos/sales/export/excel?from={month}&to={d}'),
    ('Xuất Excel hàng hóa', '/api/pos/products/export/excel'),
]

rows = []
for name, path in ENDPOINTS:
    times, size, st = [], 0, 0
    for _ in range(2):
        st, raw, ms = api.call('GET', path, raw=True)
        times.append(ms)
        size = len(raw or b'')
    rows.append({'name': name, 'path': path, 'status': st, 'ms_first': round(times[0]),
                 'ms_second': round(times[1]), 'kb': round(size / 1024, 1)})
    flag = '  <-- CHẬM' if min(times) > 1500 else ('  <-- LỚN' if size > 2_000_000 else '')
    print(f'{st} {round(times[0]):>6} {round(times[1]):>6} ms {size / 1024:>9.1f} KB  {name}{flag}')

if out:
    json.dump(rows, open(out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
