#!/usr/bin/env python3
"""Fix remaining corrupted Vietnamese in leave_screen.dart (UTF-8)."""
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
text = p.read_text(encoding="utf-8")

fixes = [
    ("Phép nam c̣n:", "Phép năm còn:"),
    ("Phép nam còn:", "Phép năm còn:"),
    ("'Phép nam'", "'Phép năm'"),
    ("Quy d?nh ngh? phép", "Quy định nghỉ phép"),
    ("'L? t?t'", "'Nghỉ lễ, Tết'"),
    ("1: 'L? t?t'", "1: 'Nghỉ lễ, Tết'"),
    ("2: 'VR c", "2: 'Việc riêng c"),
    ("3: 'VR kh", "3: 'Việc riêng kh"),
    ("4: '?m dau'", "4: 'Nghỉ ốm'"),
    ("5: 'Thai s?n'", "5: 'Thai sản'"),
    ("6: 'Ngh? bù'", "6: 'Nghỉ bù'"),
    ("7: 'Ngh? dài h?n'", "7: 'Nghỉ dài hạn'"),
    ("return 'Toàn b?'", "return 'Toàn bộ'"),
    ("return 'T?t c? NV'", "return 'Tất cả NV'"),
    ("'T?t c? nhân viên'", "'Tất cả nhân viên'"),
    ("title: 'Lo?i ngh?'", "title: 'Loại nghỉ'"),
    ("title: 'Tr?ng thái'", "title: 'Trạng thái'"),
    ("title: 'Th?i gian'", "title: 'Thời gian'"),
    ("(label: 'Toàn b?'", "(label: 'Toàn bộ'"),
    ("title: 'Chi nhánh'", "title: 'Chi nhánh'"),
    ("title: 'S? don'", "title: 'Số đơn'"),
    ("'C̣n ", "'Còn "),
    ("title: 'B? l?c'", "title: 'Bộ lọc'"),
    ("'Chua l?c'", "'Chưa lọc'"),
    ("'Các don ngh? phép s? hi?n th? t?i dây'", "'Các đơn nghỉ phép sẽ hiển thị tại đây'"),
    ("} ? ${DateFormat", "} → ${DateFormat"),
    ("'Hi?n th? ", "'Hiển thị "),
    ("Text('Hi?n th?:'", "Text('Hiển thị:'"),
    ("return 'Chua có ngày ngh?'", "return 'Chưa có ngày nghỉ'"),
    ("' · n?a ca'", "' · nửa ca'"),
    ("return '$startStr ? ${fmt.format", "return '$startStr → ${fmt.format"),
    ("label: 'S?a'", "label: 'Sửa'"),
    ("label: 'H?y'", "label: 'Hủy'"),
    ("label: 'Duy?t'", "label: 'Duyệt'"),
    ("'Duy?t $approvalStep", "'Duyệt $approvalStep"),
    ("'Lo?i ngh?'", "'Loại nghỉ'"),
    ("'Chi tr?'", "'Chi trả'"),
    ("'Gi?y BHXH'", "'Giấy BHXH'"),
    ("'Đă tr? phép năm'", "'Đã trừ phép năm'"),
    ("'Lư do'", "'Lý do'"),
    ("'Lư do t? ch?i'", "'Lý do từ chối'"),
    ("'Ngày t?o'", "'Ngày tạo'"),
    ("'Ti?n tŕnh duy?t:", "'Tiến trình duyệt:"),
    ("'Ti?n trình duy?t:", "'Tiến trình duyệt:"),
    ("'C?p ${record", "'Cấp ${record"),
    ("'Th?c hi?n:", "'Thực hiện:"),
    ("'Chi ti?t don ngh? phép'", "'Chi tiết đơn nghỉ phép'"),
    ("'Ngh? phép theo pháp lu?t'", "'Nghỉ phép theo pháp luật'"),
    ("'1. Doanh nghi?p tr? luong\\n'", "'1. Doanh nghiệp trả lương\\n'"),
    (
        "'   Phép nam, l?, vi?c riêng có luong, ngh? bù, ?m dùng phép năm.\\n\\n'",
        "'   Phép năm, lễ, việc riêng có lương, nghỉ bù, ốm dùng phép năm.\\n\\n'",
    ),
    ("'2. Không hu?ng luong\\n'", "'2. Không hưởng lương\\n'"),
    (
        "'   Vi?c riêng không luong, ngh? dài h?n không luong.\\n\\n'",
        "'   Việc riêng không lương, nghỉ dài hạn không lương.\\n\\n'",
    ),
    ("'3. BHXH & d?c bi?t\\n'", "'3. BHXH & đặc biệt\\n'"),
    (
        "'   ?m hu?ng BHXH (c?n gi?y ngh?), thai s?n DN + d?i soát BHXH.\\n\\n'",
        "'   Ốm hưởng BHXH (cần giấy nghỉ), thai sản DN + đối soát BHXH.\\n\\n'",
    ),
    (
        "'M?i ngày ngh? ch? m?t ch? d? — không v?a luong DN v?a tr? c?p BHXH.\\n'",
        "'Mỗi ngày nghỉ chỉ một chế độ — không vừa lương DN vừa trợ cấp BHXH.\\n'",
    ),
    (
        "'Ca ngh?: theo Thi?t l?p luong. Ngu?i thay ca: cùng phòng ban.'",
        "'Ca nghỉ: theo Thiết lập lương. Người thay ca: cùng phòng ban.'",
    ),
    ("title: 'H?y don ngh? phép'", "title: 'Hủy đơn nghỉ phép'"),
    ("content: 'B?n có ch?c ch?n muốn h?y don ngh? phép này?'", "content: 'Bạn có chắc chắn muốn hủy đơn nghỉ phép này?'"),
    ("confirmText: 'H?y don'", "confirmText: 'Hủy đơn'"),
    ("'Đă h?y don ngh? phép'", "'Đã hủy đơn nghỉ phép'"),
    ("'Lỗi khi h?y don'", "'Lỗi khi hủy đơn'"),
    ("title: 'Hoàn tác duy?t'", "title: 'Hoàn tác duyệt'"),
    (
        "'B?n có ch?c ch?n muốn hoàn tác tr?ng thái don ngh? phép này v? Ch? duy?t?\\nH? th?ng s? khôi ph?c l?ch làm vi?c n?u don dã du?c duy?t.'",
        "'Bạn có chắc chắn muốn hoàn tác trạng thái đơn nghỉ phép này về Chờ duyệt?\\nHệ thống sẽ khôi phục lịch làm việc nếu đơn đã được duyệt.'",
    ),
    ("'Đă hoàn tác tr?ng thái don'", "'Đã hoàn tác trạng thái đơn'"),
    ("title: 'Xóa don ngh? phép'", "title: 'Xóa đơn nghỉ phép'"),
    (
        "'B?n có ch?c ch?n muốn xóa vĩnh viễn don ngh? phép này?\\nHành d?ng này không thể hoàn tác.'",
        "'Bạn có chắc chắn muốn xóa vĩnh viễn đơn nghỉ phép này?\\nHành động này không thể hoàn tác.'",
    ),
    ("'Đă xóa don ngh? phép'", "'Đã xóa đơn nghỉ phép'"),
    ("'Lỗi khi xóa don'", "'Lỗi khi xóa đơn'"),
    ("Text('Duy?t don ngh? phép')", "Text('Duyệt đơn nghỉ phép')"),
    ("'Xác nh?n duy?t don này?'", "'Xác nhận duyệt đơn này?'"),
    ("'Sẽ trừ $daysNeeded ngày phép năm. Còn lại:", "'Sẽ trừ $daysNeeded ngày phép năm. Còn lại:"),
    ("'Phép duy?t nhưng vẫn tính công'", "'Phép duyệt nhưng vẫn tính công'"),
    ("'Đă duy?t don ngh? phép'", "'Đã duyệt đơn nghỉ phép'"),
    ("'Lỗi khi duy?t don'", "'Lỗi khi duyệt đơn'"),
    ("'T? ch?i don ngh? phép'", "'Từ chối đơn nghỉ phép'"),
    ("'Vui ḷng nh?p lư do t? ch?i:'", "'Vui lòng nhập lý do từ chối:'"),
    ("hintText: 'Lư do t? ch?i...'", "hintText: 'Lý do từ chối...'"),
    ("title: 'Thi?u thông tin'", "title: 'Thiếu thông tin'"),
    ("message: 'Vui ḷng nh?p lư do t? ch?i'", "message: 'Vui lòng nhập lý do từ chối'"),
    ("confirmLabel: 'T? ch?i'", "confirmLabel: 'Từ chối'"),
    ("'Đă t? ch?i don ngh? phép'", "'Đã từ chối đơn nghỉ phép'"),
    ("'Lỗi khi t? ch?i don'", "'Lỗi khi từ chối đơn'"),
    ("'Ch? duy?t'", "'Chờ duyệt'"),
    ("'Đă duy?t'", "'Đã duyệt'"),
    ("'T? ch?i'", "'Từ chối'"),
    ("'Đă h?y'", "'Đã hủy'"),
    ("label: 'T? ch?i'", "label: 'Từ chối'"),
    ("label: 'Xóa'", "label: 'Xóa'"),
    ("'Tính công'", "'Tính công'"),
    ("'Có · không ghi Phép trên ch?m công'", "'Có · không ghi Phép trên chấm công'"),
    ("'Phân công:", "'Phân công:"),
    ("label: Text('Thao tác')", "label: Text('Thao tác')"),
    ("'Có luong'", "'Có lương'"),
    ("title: 'Chi nhánh'", "title: 'Chi nhánh'"),
]

applied = 0
for old, new in sorted(fixes, key=lambda x: -len(x[0])):
    if old in text:
        text = text.replace(old, new)
        applied += 1

p.write_text(text, encoding="utf-8", newline="\n")
print(f"Applied {applied} fixes")

remaining = [line for line in text.splitlines() if "?" in line and "'" in line and "?" not in ("int?", "String?", "bool?", "num?", "??")]
for line in remaining[:25]:
    if any(c.isalpha() for c in line):
        pass  # count below

bad = []
for i, line in enumerate(text.splitlines(), 1):
    if "?" in line and not any(x in line for x in ["??", "int?", "String?", "bool?", "num?", "DateTime?", "Widget?", "IconData?", "VoidCallback?", "Future?", "List?", "Map?", "dynamic?", "TabController?", "StreamSubscription?", "Timer?", "double?", "TextInputType?"]):
        if "'" in line or '"' in line:
            bad.append((i, line.strip()[:100]))

print(f"Lines with ? in strings remaining: {len(bad)}")
for i, ln in bad[:20]:
    print(i, ln)
