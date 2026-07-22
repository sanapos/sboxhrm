#!/usr/bin/env python3
"""Fix approval-related and remaining corrupted Vietnamese in leave_screen.dart."""
import re
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
text = p.read_text(encoding="utf-8")

fixes = [
    # User-reported: đã duyệt, tiến trình duyệt, cấp, lịch sử phê duyệt
    ("'Đã duy?t'", "'Đã duyệt'"),
    ("'Đã h?y'", "'Đã hủy'"),
    ("'Duyệt $approvalStep/$approvalLevels c?p'", "'Duyệt $approvalStep/$approvalLevels cấp'"),
    ("'Ti?n tr\u0301nh duy?t: $currentStep/$totalLevels c?p'", "'Tiến trình duyệt: $currentStep/$totalLevels cấp'"),
    ("'Ti?n trình duy?t: $currentStep/$totalLevels c?p'", "'Tiến trình duyệt: $currentStep/$totalLevels cấp'"),
    ("'L?ch s? phê duy?t'", "'Lịch sử phê duyệt'"),
    ("'C?p ${record['stepOrder'] ?? idx + 1}'", "'Cấp ${record['stepOrder'] ?? idx + 1}'"),
    ("'Th?c hi?n: $actualUser'", "'Thực hiện: $actualUser'"),
    ("'${leave['currentApprovalStep'] ?? 0}/${leave['totalApprovalLevels']} c?p'", "'${leave['currentApprovalStep'] ?? 0}/${leave['totalApprovalLevels']} cấp'"),
    ("'Ch? duy?t'", "'Chờ duyệt'"),
    # Overview / filters
    ("Text('T?ng quan & b? l?c'", "Text('Tổng quan & bộ lọc'"),
    ("// T?ng quan + b? l?c (?n/hi?n cùng nhau)", "// Tổng quan + bộ lọc (ẩn/hiện cùng nhau)"),
    # Status / labels
    ("title: 'L?i'", "title: 'Lỗi'"),
    ("title: 'Lo?i ngh?'", "title: 'Loại nghỉ'"),
    ("title: 'Tr?ng thái'", "title: 'Trạng thái'"),
    ("title: 'Th?i gian'", "title: 'Thời gian'"),
    ("title: 'S? don'", "title: 'Số đơn'"),
    ("title: 'B? l?c'", "title: 'Bộ lọc'"),
    ("'Chua l?c'", "'Chưa lọc'"),
    ("return 'Toàn b?'", "return 'Toàn bộ'"),
    ("(label: 'Toàn b?'", "(label: 'Toàn bộ'"),
    ("return 'T?t c? NV'", "return 'Tất cả NV'"),
    ("'T?t c? nhân viên'", "'Tất cả nhân viên'"),
    ("'Các đơn nghỉ phép s? hi?n th? t?i đây'", "'Các đơn nghỉ phép sẽ hiển thị tại đây'"),
    ("'Hi?n th? ", "'Hiển thị "),
    ("Text('Hi?n th?:'", "Text('Hiển thị:'"),
    ("Quy d?nh ngh? phép", "Quy định nghỉ phép"),
    # Leave types in _getLeaveTypeInfo
    ("'VR có luong'", "'Việc riêng có lương'"),
    ("'VR không luong'", "'Việc riêng không lương'"),
    ("'?m dau'", "'Nghỉ ốm'"),
    ("'Thai s?n'", "'Thai sản'"),
    ("'Ngh? bù'", "'Nghỉ bù'"),
    ("'Ngh? dài h?n'", "'Nghỉ dài hạn'"),
    ("'L? t?t'", "'Nghỉ lễ, Tết'"),
    ("'Có luong'", "'Có lương'"),
    ("1: 'L? t?t'", "1: 'Nghỉ lễ, Tết'"),
    ("2: 'VR c", "2: 'Việc riêng c"),
    ("3: 'VR kh", "3: 'Việc riêng kh"),
    ("4: '?m dau'", "4: 'Nghỉ ốm'"),
    ("5: 'Thai s?n'", "5: 'Thai sản'"),
    ("6: 'Ngh? bù'", "6: 'Nghỉ bù'"),
    ("7: 'Ngh? dài h?n'", "7: 'Nghỉ dài hạn'"),
    # Dialogs / actions still broken
    ("'B?n có ch?c ch?n muốn hoàn tác tr?ng thái đơn nghỉ phép này v? Chờ duyệt?\\nH? th?ng s? khôi ph?c l?ch làm vi?c n?u đơn đã được duyệt.'",
     "'Bạn có chắc chắn muốn hoàn tác trạng thái đơn nghỉ phép này về Chờ duyệt?\\nHệ thống sẽ khôi phục lịch làm việc nếu đơn đã được duyệt.'"),
    ("'B?n có chắc ch?n muốn xóa vinh vi?n đơn nghỉ phép này?\\nHành d?ng này không th? hoàn tác.'",
     "'Bạn có chắc chắn muốn xóa vĩnh viễn đơn nghỉ phép này?\\nHành động này không thể hoàn tác.'"),
    ("title: 'Hủy đơn ngh? phép'", "title: 'Hủy đơn nghỉ phép'"),
    ("'Vui ḷng nh?p lý do từ chối:'", "'Vui lòng nhập lý do từ chối:'"),
    ("message: 'Vui ḷng nh?p lý do từ chối'", "message: 'Vui lòng nhập lý do từ chối'"),
    ("title: 'Thi?u thông tin'", "title: 'Thiếu thông tin'"),
    ("'Phép duy?t nhung v?n tính công'", "'Phép duyệt nhưng vẫn tính công'"),
    ("'Không ghi \"Phép\" trên b?ng chấm công'", "'Không ghi \"Phép\" trên bảng chấm công'"),
    ("child: const Text('H?y')", "child: const Text('Hủy')"),
    ("child: const Text('Duy?t')", "child: const Text('Duyệt')"),
    ("'Xác nh?n duy?t đơn này?'", "'Xác nhận duyệt đơn này?'"),
    ("'S? tr? $daysNeeded ngày phép năm. Còn l?i:", "'Sẽ trừ $daysNeeded ngày phép năm. Còn lại:"),
    ("'Từ chối đơn ngh? phép'", "'Từ chối đơn nghỉ phép'"),
    ("'Lỗi khi duy?t đơn'", "'Lỗi khi duyệt đơn'"),
    ("'Lỗi khi t? chối đơn'", "'Lỗi khi từ chối đơn'"),
    ("'Lỗi khi h?y đơn'", "'Lỗi khi hủy đơn'"),
    ("'Lỗi khi xóa đơn'", "'Lỗi khi xóa đơn'"),
    ("'Đã t? chối đơn ngh? phép'", "'Đã từ chối đơn nghỉ phép'"),
    ("'Đã duy?t đơn ngh? phép'", "'Đã duyệt đơn nghỉ phép'"),
    ("'Đã h?y đơn ngh? phép'", "'Đã hủy đơn nghỉ phép'"),
    ("'Đã xóa đơn ngh? phép'", "'Đã xóa đơn nghỉ phép'"),
    ("Text('Duy?t đơn nghỉ phép')", "Text('Duyệt đơn nghỉ phép')"),
    ("label: Text('Thao tác')", "label: Text('Thao tác')"),
    ("'Phép nam'", "'Phép năm'"),
]

applied = 0
for old, new in sorted(fixes, key=lambda x: -len(x[0])):
    if old in text:
        text = text.replace(old, new)
        applied += 1

text = text.replace("Tiến tr\u0301nh", "Tiến trình")
# Fix Unicode combining dot below on letters (common artifact)
for ch in "ệậứịụộ":
    pass
text = re.sub(r"([ăâêôơưđĂÂÊÔƠƯĐa-zA-Z])\u0323", r"\1", text)  # remove dot below
text = text.replace("c̣n", "còn").replace("C̣n", "Còn")
text = text.replace("pḥng", "phòng")

p.write_text(text, encoding="utf-8", newline="\n")
print(f"Applied {applied} groups")

skip = re.compile(
    r"\w\?\.|int\?|String\?|bool\?|num\?|Widget\?|dynamic\?|TabController\?"
    r"|Timer\?|Future\?|List\?|Map\?|double\?|DateTimeRange\?|StreamSubscription\?"
    r"|IconData\?|VoidCallback\?|TextInputType\?|DateTime\?|highlightId\?"
)
n = 0
for i, line in enumerate(text.splitlines(), 1):
    if "?" in line and not skip.search(line) and ("'" in line or "Text(" in line):
        print(f"REMAIN {i}: {line.strip()[:120]}")
        n += 1
print(f"Remaining: {n}")
