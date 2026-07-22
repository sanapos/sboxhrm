from pathlib import Path
p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
t = p.read_text(encoding="utf-8")
fixes = [
    ("'Phép nam cn:", "'Phép năm còn:"),
    ("? 'Cn ", "? 'Còn "),
    ("'Có — không ghi Phép trên ch?m công'", "'Có · không ghi Phép trên chấm công'"),
    ("'Đã tr? phép nam'", "'Đã trừ phép năm'"),
    ("'Đã hoàn tác tr?ng thái đơn', 'L?i khi hoàn tác'", "'Đã hoàn tác trạng thái đơn', 'Lỗi khi hoàn tác'"),
    ("'S? tr? $daysNeeded ngày phép nam. Cn l?i:", "'Sẽ trừ $daysNeeded ngày phép năm. Còn lại:"),
    ("'Không ghi \"Phép\" trên b?ng ch?m công'", "'Không ghi \"Phép\" trên bảng chấm công'"),
    ("'Phép nam'", "'Phép năm'"),
    ("phép nam.", "phép năm."),
    ("phép nam'", "phép năm'"),
]
for a, b in fixes:
    t = t.replace(a, b)
p.write_text(t, encoding="utf-8", newline="\n")
print("ok")
