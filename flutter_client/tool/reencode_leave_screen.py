#!/usr/bin/env python3
"""Re-encode leave_screen.dart from Windows Vietnamese to UTF-8."""
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
raw = p.read_bytes()

text = None
for enc in ("cp1258", "cp1252", "latin1"):
    try:
        text = raw.decode(enc)
        if "Tổng quan" in text or "T?ng quan" in text:
            print(f"Decoded as {enc}")
            break
    except UnicodeDecodeError:
        continue

if text is None:
    text = raw.decode("utf-8", errors="replace")
    print("Fallback utf-8 replace")

# Fix remaining ? corruption after cp1258 decode
fixes = [
    ("T?ng quan & b? l?c", "Tổng quan & bộ lọc"),
    ("T? ngày", "Từ ngày"),
    ("Đ?n ngày", "Đến ngày"),
    ("C?p nh?t", "Cập nhật"),
    ("Ti?n trình duy?t", "Tiến trình duyệt"),
    ("L?ch s? phê duy?t", "Lịch sử phê duyệt"),
    ("Lý do t? ch?i", "Lý do từ chối"),
    ("T? ch?i", "Từ chối"),
    ("mu?n", "muốn"),
    ("H?y đơn", "Hủy đơn"),
    ("H?y don", "Hủy đơn"),
    ("đơn nghỉ phép này", "đơn nghỉ phép này"),  # noop check
    ("Hoàn tác duy?t", "Hoàn tác duyệt"),
    ("Ch? duy?t", "Chờ duyệt"),
    ("Đã duy?t", "Đã duyệt"),
    ("Đã h?y", "Đã hủy"),
    ("Xác nh?n duy?t", "Xác nhận duyệt"),
    ("Phép duy?t nhưng vẫn tính công", "Phép duyệt nhưng vẫn tính công"),
    ("Vui lòng nh?p lý do t? ch?i", "Vui lòng nhập lý do từ chối"),
    ("Thi?u thông tin", "Thiếu thông tin"),
    ("L?i khi", "Lỗi khi"),
    ("S? tr?", "Sẽ trừ"),
    ("phép nam", "phép năm"),
    ("Còn l?i", "Còn lại"),
    ("N?a ca", "Nửa ca"),
    ("S? ngày", "Số ngày"),
    ("Ngu?i thay", "Người thay"),
    ("Ca làm vi?c", "Ca làm việc"),
    ("Tính công", "Tính công"),
    ("ch?m công", "chấm công"),
    ("Đã tr? phép nam", "Đã trừ phép năm"),
    ("Chi ti?t đơn", "Chi tiết đơn"),
    ("Nghỉ phép theo pháp luật", "Nghỉ phép theo pháp luật"),
    ("vinh vi?n", "vĩnh viễn"),
    ("không th? hoàn tác", "không thể hoàn tác"),
    ("c?p", "cấp"),  # careful - might over-replace
]

# Apply fixes carefully - longer strings first
fixes_sorted = sorted(fixes, key=lambda x: -len(x[0]))
for old, new in fixes_sorted:
    if old != new:
        text = text.replace(old, new)

# Specific multi-word fixes that need context
text = text.replace(
    "Bạn có chắc chắn muốn hủy đơn nghỉ phép này?",
    "Bạn có chắc chắn muốn hủy đơn nghỉ phép này?",
)
text = text.replace("Đã hủy đơn nghỉ phép", "Đã hủy đơn nghỉ phép")
text = text.replace("Lỗi khi hủy đơn", "Lỗi khi hủy đơn")

p.write_text(text, encoding="utf-8", newline="\n")
print("Wrote UTF-8", p)

# verify
out = p.read_text(encoding="utf-8")
checks = ["Tổng quan & bộ lọc", "Đến ngày", "Tiến trình duyệt", "Lịch sử phê duyệt"]
for c in checks:
    print(c, "OK" if c in out else "MISSING")
