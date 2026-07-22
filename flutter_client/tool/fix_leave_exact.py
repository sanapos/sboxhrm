from pathlib import Path

p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
t = p.read_text(encoding="utf-8")

fixes = [
    ("'Phép nam còn:", "'Phép năm còn:"),
    (
        "'Ca ngh?: theo Thi?t l?p luong. Ngu?i thay ca: cùng pḥng ban.'",
        "'Ca nghỉ: theo Thiết lập lương. Người thay ca: cùng phòng ban.'",
    ),
    (
        "'Sẽ trừ $daysNeeded ngày phép năm. Còn l?i: $balanceRemaining ngày.'",
        "'Sẽ trừ $daysNeeded ngày phép năm. Còn lại: $balanceRemaining ngày.'",
    ),
    (
        "// LEAVE CARD — 3 ḍng (tên · lo?i · ngày ngh?)",
        "// LEAVE CARD — 3 dòng (tên · loại · ngày nghỉ)",
    ),
    ("// Ḍng 2 — lo?i ngh?", "// Dòng 2 — loại nghỉ"),
    (
        "// Ḍng 3 — ngày xin ngh? (d? dd/MM/yyyy)",
        "// Dòng 3 — ngày xin nghỉ (đủ dd/MM/yyyy)",
    ),
    (
        "// Delete: có quy?n xóa module — NV xóa đơn pending c?a ḿnh; QL xóa trên tab qu?n lư",
        "// Delete: có quyền xóa module — NV xóa đơn pending của mình; QL xóa trên tab quản lý",
    ),
    ("// Ḍng 1 — nhân viên + trạng thái", "// Dòng 1 — nhân viên + trạng thái"),
]

missing = []
for a, b in fixes:
    if a not in t:
        missing.append(a[:70])
    else:
        t = t.replace(a, b)

p.write_text(t, encoding="utf-8", newline="\n")
report = Path(__file__).resolve().parent / "fix_leave_exact_report.txt"
report.write_text(
    "missing:\n" + "\n".join(missing) if missing else "all fixed",
    encoding="utf-8",
)
