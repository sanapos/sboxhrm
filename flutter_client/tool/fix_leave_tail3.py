from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
t = p.read_text(encoding="utf-8")
subs = [
    ("khôi ph?c l?ch làm vi?c", "khôi phục lịch làm việc"),
    ("không th? hoàn tác", "không thể hoàn tác"),
    ("Còn l?i:", "Còn lại:"),
    ("'Đã h?y'", "'Đã hủy'"),
    ("lo?i ngh?", "loại nghỉ"),
    ("d? dd/MM", "đủ dd/MM"),
    ("quy?n xóa", "quyền xóa"),
    ("c?a m\u0301nh", "của mình"),
    ("qu?n lư", "quản lý"),
    ("T?ng quan + b? l?c", "Tổng quan + bộ lọc"),
    ("(?n/hi?n", "(ẩn/hiện"),
    ("d\u0323ng", "dòng"),
    ("D\u0323ng", "Dòng"),
]
for a, b in subs:
    t = t.replace(a, b)
p.write_text(t, encoding="utf-8", newline="\n")
