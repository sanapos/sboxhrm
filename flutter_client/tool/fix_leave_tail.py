from pathlib import Path
p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
t = p.read_text(encoding="utf-8")
fixes = [
    ("ngày xin ngh? (đủ", "ngày xin nghỉ (đủ"),
    ("hintText: 'Lư do t? ch?i...'", "hintText: 'Lý do từ chối...'"),
    ("message: 'Vui ḷng nh?p lư do t? ch?i'", "message: 'Vui lòng nhập lý do từ chối'"),
    ("// Ḍng 3", "// Dòng 3"),
]
for a, b in fixes:
    t = t.replace(a, b)
p.write_text(t, encoding="utf-8", newline="\n")
