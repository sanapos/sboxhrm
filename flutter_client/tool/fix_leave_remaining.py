"""Fix remaining corrupted Vietnamese strings in leave_screen.dart (UTF-8 safe)."""
from pathlib import Path
import re
import unicodedata

p = Path(__file__).resolve().parents[1] / "lib/screens/leave_screen.dart"
t = p.read_text(encoding="utf-8")

# Normalize decomposed Vietnamese (c + combining marks -> precomposed)
t = unicodedata.normalize("NFC", t)

fixes = [
    ("'Phép nam còn:", "'Phép năm còn:"),
    ("'Phép nam cn:", "'Phép năm còn:"),
    ("? 'Còn ", "? 'Còn "),  # no-op anchor
    ("'Còn ${", "'Còn ${"),  # already ok after NFC
    ("'Duy?t ", "'Duyệt "),
    ("'Tr?ng thái'", "'Trạng thái'"),
    (
        "'Ca ngh?: theo Thi?t l?p luong. Ngu?i thay ca: cùng phòng ban.'",
        "'Ca nghỉ: theo Thiết lập lương. Người thay ca: cùng phòng ban.'",
    ),
    (
        "'Bạn có chắc chắn muốn hoàn tác trạng thái đơn nghỉ phép này v? Chờ duyệt?\\nHệ thống s? khôi phục lịch làm việc n?u don đã được duyệt.'",
        "'Bạn có chắc chắn muốn hoàn tác trạng thái đơn nghỉ phép này về Chờ duyệt?\\nHệ thống sẽ khôi phục lịch làm việc nếu đơn đã được duyệt.'",
    ),
    (
        "'Bạn có chắc chắn muốn xóa vinh vi?n đơn nghỉ phép này?\\nHành d?ng này không th? hoàn tác.'",
        "'Bạn có chắc chắn muốn xóa vĩnh viễn đơn nghỉ phép này?\\nHành động này không thể hoàn tác.'",
    ),
    (
        "'Sẽ trừ $daysNeeded ngày phép năm. Còn l?i: $balanceRemaining ngày.'",
        "'Sẽ trừ $daysNeeded ngày phép năm. Còn lại: $balanceRemaining ngày.'",
    ),
    # Comments (cosmetic)
    ("// T?ng quan + b? l?c (?n/hi?n cùng nhau)", "// Tổng quan + bộ lọc (ẩn/hiện cùng nhau)"),
    ("// LEAVE CARD — 3 ḍng (tên · lo?i · ngày ngh?)", "// LEAVE CARD — 3 dòng (tên · loại · ngày nghỉ)"),
    ("// Ḍng 2 — lo?i ngh?", "// Dòng 2 — loại nghỉ"),
    ("// Ḍng 3 — ngày xin ngh? (d? dd/MM/yyyy)", "// Dòng 3 — ngày xin nghỉ (đủ dd/MM/yyyy)"),
    ("// Delete: có quy?n xóa module — NV xóa đơn pending c?a ḿnh; QL xóa trên tab qu?n lư",
     "// Delete: có quyền xóa module — NV xóa đơn pending của mình; QL xóa trên tab quản lý"),
]

for old, new in fixes:
    if old not in t and "no-op" not in old:
        pass  # optional missing
    t = t.replace(old, new)

# Fix decomposed chars that survived
t = t.replace("c\u0323n", "còn")  # c + dot below + n
t = t.replace("C\u0323n", "Còn")
t = t.replace("ph\u0323ng", "phòng")
t = t.replace("d\u0323ng", "dòng")
t = t.replace("m\u0301nh", "mình")
t = t.replace("l\u01b0 ", "lý ")  # unlikely

p.write_text(t, encoding="utf-8", newline="\n")

# Report suspicious string literals still containing ?
suspect = []
for i, line in enumerate(t.splitlines(), 1):
    if "?" not in line:
        continue
    # skip Dart null-aware / ternary
    stripped = line.strip()
    if stripped.startswith("//"):
        if "?" in stripped and not any(x in stripped for x in ["??", "?.", "? ", " ? ", ")?", ": ?", "is ?", "as ?"]):
            suspect.append((i, line.strip()[:120]))
        continue
    # find quoted strings with ?
    for m in re.finditer(r"'([^'\\]|\\.)*'|\"([^\"\\]|\\.)*\"", line):
        s = m.group(0)
        if "?" in s and "??" not in s and "?." not in s and "${" not in s:
            # allow trailing question mark in confirm dialogs
            if s.endswith("?'") or s.endswith('?"'):
                continue
            suspect.append((i, s[:100]))

out = Path(__file__).resolve().parent / "leave_strings_check.txt"
out.write_text(
    "\n".join(f"L{n}: {s}" for n, s in suspect) or "OK: no suspicious strings",
    encoding="utf-8",
)
print(f"Wrote {out.name}, {len(suspect)} suspects")
