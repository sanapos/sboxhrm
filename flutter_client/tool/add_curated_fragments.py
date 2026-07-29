"""Merge hand-written translations for the fragments tr() still cannot cover.

Machine translation gets domain terms wrong ("phiếu" as vote, "duyệt" as browse),
so these are written by hand and overwrite any earlier automatic value.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
JSON = os.path.join(HERE, 'en_ui_map.json')

CURATED = {
    # Wrong sense from machine translation
    'Hủy phiếu': 'Void note',
    'trên HĐ': 'on invoice',
    'Bạn có chắc muốn duyệt tất cả': 'Are you sure you want to approve all',
    'duyệt tất cả': 'approve all',
    'Tất cả sẽ được thêm vào': 'All will be added to',
    'Chọn nhân viên khác để thay đổi.': 'Pick another employee to change.',
    'khác để thay đổi': 'to change',

    # Device / attendance
    'đã kết nối': 'connected',
    'đã ngắt kết nối': 'disconnected',
    'Chưa kích hoạt': 'Not activated',
    'Chấm gần nhất': 'Last punch',
    'đổi máy': 'device change',
    'Đã ghi dữ liệu thô': 'Raw data recorded',
    'Đã xóa dữ liệu': 'Data deleted',
    'Đã lưu phân quyền cho': 'Permissions saved for',
    'Vui lòng chia sẻ quyền Viewer cho': 'Please grant Viewer access to',

    # Warehouse / POS documents
    'Số': 'No.',
    'Ngày xuất': 'Issue date',
    'Phiếu nhập': 'Goods receipt',
    'phiếu tới': 'notes to',
    'đã gửi tới': 'sent to',
    'Trừ lại kho, hoàn tác tiền trên đơn': 'Restore stock and refund the order',
    'Phiếu chi đã được tạo.': 'A payment voucher has been created.',
    'Phiếu thu đã được tạo.': 'A receipt voucher has been created.',
    'hao hụt': 'shortage',
    'thừa': 'surplus',
    'khớp': 'matched',
    'vấn đề': 'issues',
    'chưa gửi': 'not sent',
    'Hết BH': 'Warranty ends',
    'Hết hiệu lực': 'Expires',
    'Thiếu giấy tờ cho khoản': 'Missing documents for',
    'THỰC ĐƠN TUẦN': 'WEEKLY MENU',

    # Misc labels. "Ô"/"ô" (a grid cell) carries the trailing or leading space so it
    # stays two characters long and never substitutes inside a word.
    'Ô ': 'Cell ',
    ' ô': ' cells',
    # Default checklist rows in the rich-text editor template. Longest-first
    # ordering keeps "Mục tiêu" and friends matching ahead of this.
    'Mục ': 'Item ',
    'hoạt động': 'active',
    'người nhận': 'recipients',
    'chỗ': 'seats',
    'Gói': 'Plan',
    'Đoàn phí': 'Union dues',
    'Tiêu đề mẫu': 'Sample title',
    'nào được gán': 'assigned',
    'để xem hướng dẫn chi tiết': 'for detailed instructions',
    'mỗi dòng một URL': 'one URL per line',
    'Zalo hỗ trợ': 'Zalo support',
    'Nội dung (hỗ trợ {variable})': 'Content (supports {variable})',
    'Nội dung tuỳ biến (override, hỗ trợ {var})':
        'Custom content (override, supports {var})',
}

data = json.load(open(JSON, encoding='utf-8'))
changed = {k: v for k, v in CURATED.items() if data.get(k) != v}
data.update(CURATED)
json.dump(data, open(JSON, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(f'curated {len(CURATED)}, changed {len(changed)}, map total {len(data)}')

subprocess.run([sys.executable, os.path.join(HERE, 'generate_en_ui_map_dart.py')],
               check=True)
