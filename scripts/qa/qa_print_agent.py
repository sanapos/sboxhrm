"""Test in qua Agent: gửi lệnh in bằng API (vai máy gửi), máy Agent (vd. C20) nhận và in ra máy in giả.

  python -I scripts/qa/qa_print_agent.py Hotel basic           # in thử, phiếu bếp JSON, ESC/POS ảnh, tem TSPL, chống trùng
  python -I scripts/qa/qa_print_agent.py Hotel enqueue          # chỉ tạo 1 lệnh, in jobId (test Agent tắt / máy in tắt)
  python -I scripts/qa/qa_print_agent.py Hotel status <jobId>   # xem trạng thái
  python -I scripts/qa/qa_print_agent.py Hotel retry <jobId>    # in lại lệnh lỗi
"""
import base64
import glob
import json
import os
import sys
import time
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_e2e as q  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
BASE = 'http://127.0.0.1:7070'
PRINTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'prints')
STATUS = {0: 'Queued', 1: 'Claimed', 2: 'Printing', 3: 'Completed', 4: 'Failed', 5: 'Cancelled', 6: 'Expired'}


def api(ind):
    # Dùng lại token (≈10 phút): mỗi lần đăng nhập thêm 1 phiên, server chỉ giữ 10 phiên/tài khoản
    # → chạy script nhiều lần sẽ đẩy phiên của máy POS ra (máy bị đăng xuất).
    cache = os.path.join(os.environ.get('TEMP', '.'), f'qa_token_{ind}.json')
    try:
        c = json.load(open(cache))
        if time.time() - c['at'] < 600:
            return q.Api(BASE, c['token'])
    except Exception:
        pass
    _, _, _, token = q.login(BASE, q.load_accounts()[ind])
    json.dump({'at': time.time(), 'token': token}, open(cache, 'w'))
    return q.Api(BASE, token)


def cloud_printer(a):
    st, js, _ = a.call('GET', '/api/pos/printers')
    rows = (js or {}).get('data') or []
    cloud = [p for p in rows if not p.get('isDeviceLocal') and p.get('isActive', True)]
    if not cloud:
        sys.exit('Cửa hàng chưa có máy in cloud (chưa chia sẻ Agent)')
    return cloud[0]


def enqueue(a, printer_id, doc, fmt, payload, ref, client_id=None):
    body = {'documentType': doc, 'payloadFormat': fmt, 'payload': payload, 'copies': 1,
            'referenceNo': ref, 'printerId': printer_id}
    if client_id:
        body['clientRequestId'] = client_id
    st, js, ms = a.call('POST', '/api/pos/print-jobs', body)
    return st, js, ms


def status(a, job_id):
    st, js, _ = a.call('GET', f'/api/pos/print-jobs/{job_id}')
    d = (js or {}).get('data') or {}
    s = d.get('status')
    return STATUS.get(s, s), d.get('errorCode'), d.get('errorMessage')


def wait_done(a, job_id, timeout=40):
    t0 = time.time()
    last = None
    while time.time() - t0 < timeout:
        s, code, msg = status(a, job_id)
        last = (s, code, msg)
        if s in ('Completed', 'Failed', 'Cancelled', 'Expired'):
            return s, time.time() - t0, code, msg
        time.sleep(0.4)
    return (last[0] if last else '?'), time.time() - t0, None, 'timeout'


def prints_count():
    return len(glob.glob(os.path.join(PRINTS, '*.bin')))


def latest_bin(pred):
    for f in sorted(glob.glob(os.path.join(PRINTS, '*.bin')), key=os.path.getmtime, reverse=True):
        txt = f[:-4] + '.txt'
        info = open(txt, encoding='utf-8', errors='replace').read() if os.path.exists(txt) else ''
        if pred(info):
            return open(f, 'rb').read()
    return None


def basic(a):
    p = cloud_printer(a)
    pid = p['id']
    print(f"Máy cloud: {p['name']} ({pid[:8]})")
    now = time.strftime('%H%M%S')
    kitchen = json.dumps({
        'tableName': 'Phòng QA 1', 'areaName': 'Khu QA', 'senderName': 'Máy gửi QA',
        'orderNo': 'QA' + now, 'isCancel': False, 'sentAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'lines': [{'productName': 'Phở bò tái', 'qty': 2, 'unitName': 'tô', 'note': 'Ít hành'},
                  {'productName': 'Trà đá', 'qty': 2, 'unitName': 'ly'}],
    }, ensure_ascii=False)
    raster = latest_bin(lambda t: 'ESC/POS' in t and 'raster_blocks' in t)
    tspl = latest_bin(lambda t: 'TSPL' in t)
    cases = [
        ('Phiếu bếp (KitchenSlipJson)', 'KitchenSlip', 'KitchenSlipJson', kitchen),
    ]
    if raster:
        cases.append(('Hóa đơn ảnh ESC/POS', 'SaleInvoice', 'EscPosBase64', base64.b64encode(raster).decode()))
    if tspl:
        cases.append(('Tem TSPL', 'BarcodeLabel', 'EscPosBase64', base64.b64encode(tspl).decode()))
    ok_all = True
    for name, doc, fmt, payload in cases:
        before = prints_count()
        st, js, ms = enqueue(a, pid, doc, fmt, payload, f'QA-{now}-{doc}')
        if st != 200 or not (js or {}).get('isSuccess'):
            print(f'  ✗ {name}: HTTP {st} {(js or {}).get("message")}')
            ok_all = False
            continue
        d = js['data']
        s, secs, code, msg = wait_done(a, d['jobId'])
        time.sleep(0.6)
        printed = prints_count() - before
        ok = s == 'Completed' and printed >= 1
        ok_all &= ok
        print(f"  {'✓' if ok else '✗'} {name}: {s} sau {secs:.1f}s · agentOnline={d.get('agentOnlineForPrinter')} "
              f"· ra giấy={printed}{'' if not code else ' · ' + str(code) + ' ' + str(msg)}")

    # Chống in trùng: gửi lại cùng clientRequestId → không tạo lệnh thứ hai.
    cid = str(uuid.uuid4())
    before = prints_count()
    st1, js1, _ = enqueue(a, pid, 'KitchenSlip', 'KitchenSlipJson', kitchen, f'QA-{now}-dup', cid)
    st2, js2, _ = enqueue(a, pid, 'KitchenSlip', 'KitchenSlipJson', kitchen, f'QA-{now}-dup', cid)
    j1 = ((js1 or {}).get('data') or {}).get('jobId')
    j2 = ((js2 or {}).get('data') or {}).get('jobId')
    if j1:
        wait_done(a, j1)
    time.sleep(2)
    printed = prints_count() - before
    dup_ok = j1 is not None and j1 == j2 and printed == 1
    ok_all &= dup_ok
    print(f"  {'✓' if dup_ok else '✗'} Gửi trùng clientRequestId: job1={str(j1)[:8]} job2={str(j2)[:8]} ra giấy={printed}")

    # Máy in không tồn tại → báo lỗi rõ, không treo.
    st, js, _ = enqueue(a, str(uuid.uuid4()), 'SaleInvoice', 'TestPrintJson', '{}', f'QA-{now}-bad')
    bad_ok = st == 400 or not (js or {}).get('isSuccess')
    ok_all &= bad_ok
    print(f"  {'✓' if bad_ok else '✗'} Máy in không tồn tại: HTTP {st} · {(js or {}).get('message')}")
    print('KẾT QUẢ:', 'ĐẠT' if ok_all else 'CÓ LỖI')


def main():
    ind, cmd = sys.argv[1], sys.argv[2]
    a = api(ind)
    if cmd == 'basic':
        basic(a)
    elif cmd == 'enqueue':
        p = cloud_printer(a)
        st, js, _ = enqueue(a, p['id'], 'KitchenSlip', 'KitchenSlipJson', json.dumps({'tableName': 'QA', 'lines': [{'productName': 'Món test', 'qty': 1}]}), 'QA-' + time.strftime('%H%M%S'))
        print(json.dumps((js or {}).get('data'), ensure_ascii=False))
    elif cmd == 'status':
        print(status(a, sys.argv[3]))
    elif cmd == 'retry':
        st, js, _ = a.call('POST', f'/api/pos/print-jobs/{sys.argv[3]}/retry')
        print(st, json.dumps(js, ensure_ascii=False)[:300])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
