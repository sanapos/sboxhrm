from pathlib import Path
p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
t = p.read_text(encoding="utf-8")
fixes = [
    ("'T? ch?i'", "'Từ chối'"),
    ("'Lư do t? ch?i'", "'Lý do từ chối'"),
    ("'Lư do'", "'Lý do'"),
    ("'Đã h?y đơn nghỉ phép'", "'Đã hủy đơn nghỉ phép'"),
    ("'Đã hoàn tác trạng thái don'", "'Đã hoàn tác trạng thái đơn'"),
    ("'Đã t? ch?i đơn nghỉ phép'", "'Đã từ chối đơn nghỉ phép'"),
    ("'Lỗi khi t? chối don'", "'Lỗi khi từ chối đơn'"),
    ("'Vui ḷng nh?p lư do t? ch?i:'", "'Vui lòng nhập lý do từ chối:'"),
    ("hintText: 'Lư do t? ch?i...'", "hintText: 'Lý do từ chối...'"),
    ("message: 'Vui ḷng nh?p lư do t? ch?i'", "message: 'Vui lòng nhập lý do từ chối'"),
    ("t? ch?i", "từ chối"),
    ("T? ch?i", "Từ chối"),
    ("Lư do", "Lý do"),
    ("ḷng nh?p", "lòng nhập"),
    ("trạng thái don'", "trạng thái đơn'"),
]
for a, b in fixes:
    t = t.replace(a, b)
p.write_text(t, encoding="utf-8", newline="\n")
