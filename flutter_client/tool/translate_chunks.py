"""Translate the VN UI chunks, preferring a curated dictionary for domain/short terms."""
import json
import os
import sys
import time

from deep_translator import GoogleTranslator

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'chunks_en.json')

# Domain terms and short words that machine translation gets wrong in context.
CURATED = {
    'và': 'and', 'Kỳ': 'Period', 'Nợ': 'Debt', 'Đã': 'Done', 'vào': 'in',
    'bài': 'posts', 'món': 'items', 'TBị': 'devices', 'chờ': 'pending',
    'đợt': 'batches', 'bàn': 'tables', 'mục': 'items', 'Cấp': 'Level',
    'bếp': 'kitchen', 'Bởi': 'By', 'Còn': 'Remaining', 'cấp': 'level',
    'lỗi': 'errors', 'đến': 'to', 'mới': 'new', 'Khổ': 'Size', 'Lần': 'Time',
    'Máy': 'Device', 'Mẫu': 'Template', 'Mốc': 'Milestone', 'MỨC': 'LEVEL',
    'Sớm': 'Early', 'Trễ': 'Late', 'ảnh': 'images', 'lượt': 'times',
    'dòng': 'rows', 'tuần': 'weeks', 'buổi': 'sessions', 'công': 'workdays',
    'nhóm': 'groups', 'Bước': 'Step', 'Chốt': 'Close', 'suất': 'portions',
    'Lệch': 'Variance', 'Suất': 'Portion', 'ca': 'shifts', 'ngày': 'days',
    'giờ': 'hours', 'phút': 'minutes', 'tháng': 'months', 'năm': 'years',
    'lần': 'times', 'ra': 'out', 'đơn': 'orders', 'phiếu': 'slips',
    'sản phẩm': 'products', 'mặt hàng': 'items', 'nhân viên': 'employees',
    'khách': 'customers', 'hàng hóa': 'goods', 'hoá đơn': 'invoices',
    'hóa đơn': 'invoices', 'công việc': 'tasks', 'đơn vị': 'units',
    'yêu cầu': 'requests', 'phản hồi': 'replies', 'mức giá': 'price levels',
    'dòng giá': 'price rows', 'Tồn kho': 'Stock', 'đã kiểm': 'checked',
    'chưa thiết lập lương': 'have no salary setup',
    'phiếu trả hàng': 'return slips',
    'module được cấp quyền': 'modules granted',
    'khách còn nợ': 'customers with debt',
    'đơn cần được xử lý': 'orders need processing',
    'sản phẩm đang in trên máy này': 'products printing on this device',
    # Templates the source scanner truncates at a nested ${map['key']}.
    'Bạn có chắc muốn xóa yêu cầu của':
        'Are you sure you want to delete the request of',
    'Bạn có chắc muốn hoàn duyệt yêu cầu của':
        'Are you sure you want to revert the approval of the request of',
    'Các hàng hóa đang gắn nhóm sẽ mất liên kết':
        'Goods attached to the group will lose their link',
    'đã nằm trong combo': 'is already in the combo',
    'nhân viên cho': 'employees for',
    'Xóa mẫu': 'Delete template', 'Hủy phiếu': 'Cancel slip',
    'Xóa': 'Delete', 'điểm': 'points', 'Ô': 'Cell',
    'Xuất lúc': 'Exported at', 'Lý do': 'Reason', 'Nhân viên': 'Employee',
    'Ghi chú': 'Note', 'Từ ngày': 'From', 'Kỳ lương': 'Pay period',
    'Thực đơn tuần': 'Weekly menu', 'Loại': 'Type', 'Máy in': 'Printer',
    'Tích điểm': 'Accumulate points', 'HĐ': 'Invoice', 'điểm': 'points',
}


def main():
    need = json.load(open(os.path.join(HERE, 'chunks_need.json'),
                         encoding='utf-8'))
    done = {}
    if os.path.exists(OUT):
        done = json.load(open(OUT, encoding='utf-8'))

    todo = [s for s in need if s not in done]
    print(f'to translate: {len(todo)} (resuming with {len(done)} done)')

    tx = GoogleTranslator(source='vi', target='en')
    batch, batch_len = [], 0
    for i, s in enumerate(need):
        if s in done:
            continue
        if s in CURATED:
            done[s] = CURATED[s]
            continue
        batch.append(s)
        batch_len += len(s) + 1
        if batch_len > 3500 or len(batch) >= 40:
            _flush(tx, batch, done)
            batch, batch_len = [], 0
            json.dump(done, open(OUT, 'w', encoding='utf-8'),
                      ensure_ascii=False, indent=1)
            print(f'  progress {len(done)}/{len(need)}', flush=True)
            time.sleep(0.4)
    if batch:
        _flush(tx, batch, done)

    for k, v in CURATED.items():
        done[k] = v
    json.dump(done, open(OUT, 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print('done', len(done), '->', OUT)


def _flush(tx, batch, done):
    try:
        res = tx.translate_batch(batch)
    except Exception as e:  # fall back to one-by-one
        print('  batch failed, retry single:', e, file=sys.stderr)
        res = []
        for s in batch:
            try:
                res.append(tx.translate(s))
            except Exception:
                res.append(s)
            time.sleep(0.25)
    for s, t in zip(batch, res):
        done[s] = (t or s).strip()


if __name__ == '__main__':
    main()
