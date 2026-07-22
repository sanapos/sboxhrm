#!/usr/bin/env python3
"""Final UTF-8 cleanup for leave_screen approval strings."""
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
t = p.read_text(encoding="utf-8")

fixes = [
    ("'Đă duy?t'", "'Đã duyệt'"),
    ("'Đã duy?t'", "'Đã duyệt'"),
    ("'Đă h?y'", "'Đã hủy'"),
    ("'Đă ", "'Đã "),
    ("duy?t", "duyệt"),
    ("c?p'", "cấp'"),
    ("c?p,", "cấp,"),
    ("c?p)", "cấp)"),
    ("c?p:", "cấp:"),
    ("Ti?n tr\u0301nh", "Tiến trình"),
    ("Ti?n trình", "Tiến trình"),
    ("Th?c hi?n", "Thực hiện"),
    ("tr?ng thái", "trạng thái"),
    ("B?n có ch?c ch?n", "Bạn có chắc chắn"),
    ("mu?n", "muốn"),
    ("H? th?ng", "Hệ thống"),
    ("khôi ph?c", "khôi phục"),
    ("l?ch làm vi?c", "lịch làm việc"),
    ("dă du?c", "đã được"),
    ("dã du?c", "đã được"),
    ("don ngh? phép", "đơn nghỉ phép"),
    ("don nghỉ phép", "đơn nghỉ phép"),
    ("duy?t don", "duyệt đơn"),
    ("t? chối don", "từ chối đơn"),
    ("h?y don", "hủy đơn"),
    ("xóa don", "xóa đơn"),
    ("Ch? duy?t", "Chờ duyệt"),
    ("v? Ch?", "về Chờ"),
    ("S? tr?", "Sẽ trừ"),
    ("phép nam", "phép năm"),
    ("Cn l?i", "Còn lại"),
    ("Phép nam cn", "Phép năm còn"),
    ("? 'Cn ", "? 'Còn "),
    ("ch?m công", "chấm công"),
    ("b?ng ch", "bảng ch"),
    ("tr? phép", "trừ phép"),
    ("L?i khi", "Lỗi khi"),
]
for a, b in sorted(fixes, key=lambda x: -len(x[0])):
    t = t.replace(a, b)

p.write_text(t, encoding="utf-8", newline="\n")

# verify
bad = [line for i, line in enumerate(t.splitlines(), 1) if "?" in line and "'" in line and "?." not in line and "??" not in line and "int?" not in line and "String?" not in line]
print("lines with ? in strings:", len(bad))
for line in bad[:15]:
    if "duy" in line or "cấp" in line or "phê" in line or "Đã" in line:
        print(line.strip()[:100])

assert "Đã duyệt" in t
assert "Tiến trình duyệt" in t
assert "duy?t" not in t
assert "c?p" not in t
print("OK")
