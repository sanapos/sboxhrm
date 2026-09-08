#!/usr/bin/env python3
"""Fix corrupted Vietnamese strings (U+FFFD, ? placeholders) in Flutter lib."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "flutter_client/lib"

TARGETS = [
    LIB / "screens/device_users_screen.dart",
    LIB / "screens/attendance/payroll_summary_tab.dart",
]

# Order: longer patterns first
REPLACEMENTS: list[tuple[str, str]] = [
    # ── device users / payroll common phrases ──
    ("Chọn máy để tải danh sách nhân viên:", "Chọn máy để tải danh sách nhân viên:"),
    ("Đang gửi lệnh tải nhân viên từ máy...", "Đang gửi lệnh tải nhân viên từ máy..."),
    ("Tải hồ sơ nhân sự xuống máy", "Tải hồ sơ nhân sự xuống máy"),
    ("Vui lòng chọn thiết bị để xem nhân viên", "Vui lòng chọn thiết bị để xem nhân viên"),
    ("nhân viên chưa có trên máy chấm công", "nhân viên chưa có trên máy chấm công"),
    ("Chọn thiết bị để xem danh sách nhân viên", "Chọn thiết bị để xem danh sách nhân viên"),
    ("Tất cả nhân viên đã có trên máy chấm công", "Tất cả nhân viên đã có trên máy chấm công"),
    ("Không có user đã liên kết", "Không có user đã liên kết"),
    ("Liên kết user máy chấm công với hồ sơ nhân sự", "Liên kết user máy chấm công với hồ sơ nhân sự"),
    ("Không có user chưa liên kết", "Không có user chưa liên kết"),
    ("Tất cả user trên máy đã được liên kết nhân sự", "Tất cả user trên máy đã được liên kết nhân sự"),
    ("Không có user trên thiết bị online", "Không có user trên thiết bị online"),
    ("Chưa có thiết bị online hoặc chưa có user trên các máy đang kết nối", "Chưa có thiết bị online hoặc chưa có user trên các máy đang kết nối"),
    ("Thêm user hoặc đồng bộ từ nhân viên", "Thêm user hoặc đồng bộ từ nhân viên"),
    ("Nhân viên tải thất bại", "Nhân viên tải thất bại"),
    ("Thành công", "Thành công"),
    ("Đang lọc", "Đang lọc"),
    ("Bộ lọc", "Bộ lọc"),
    ("Tổng quan", "Tổng quan"),
    ("Đang tải...", "Đang tải..."),
    ("Chưa có thiết bị", "Chưa có thiết bị"),
    ("Hãy kết nối máy chấm công trước", "Hãy kết nối máy chấm công trước"),
    ("Không tìm thấy user", "Không tìm thấy user"),
    ("Thử từ khóa khác hoặc bộ lọc tổng quan", "Thử từ khóa khác hoặc bộ lọc tổng quan"),
    ("Chưa có chi nhánh", "Chưa có chi nhánh"),
    ("Hiển thị", "Hiển thị"),
    ("Quản trị viên", "Quản trị viên"),
    ("Người dùng", "Người dùng"),
    ("Ngón cái", "Ngón cái"),
    ("Ngón trỏ", "Ngón trỏ"),
    ("Ngón giữa", "Ngón giữa"),
    ("Ngón áp út", "Ngón áp út"),
    ("Ngón út", "Ngón út"),
    ("tay trái", "tay trái"),
    ("tay phải", "tay phải"),
    ("không dấu", "không dấu"),
    ("có dấu", "có dấu"),
    ("bên dưới", "bên dưới"),
    ("Nhập tên có dấu, sẽ tự động sinh tên không dấu bên dưới", "Nhập tên có dấu, sẽ tự động sinh tên không dấu bên dưới"),
    ("Không thể tạo file Excel", "Không thể tạo file Excel"),
    ("Đã xuất Excel", "Đã xuất Excel"),
    ("Lỗi xuất Excel", "Lỗi xuất Excel"),
    ("Không có dữ liệu để xuất", "Không có dữ liệu để xuất"),
    ("Tránh AlertDialog Column không cuộn ở màn hình thấp không bấm được", "Tránh AlertDialog Column không cuộn ở màn hình thấp không bấm được"),
    ("Bắt đầu polling kiểm tra trạng thái", "Bắt đầu polling kiểm tra trạng thái"),
    ("ZKTeco chỉ có 2 loại: 0 = Người dùng, 14 = Quản trị viên", "ZKTeco chỉ có 2 loại: 0 = Người dùng, 14 = Quản trị viên"),
    # payroll_summary_tab
    ("Đọc phụ cấp từ danh mục — cùng thuật toán màn Thiết lập lương.", "Đọc phụ cấp từ danh mục — cùng thuật toán màn Thiết lập lương."),
    ("Shift salary fallback (Thiết lập lương → Lương ca cố định)", "Shift salary fallback (Thiết lập lương → Lương ca cố định)"),
]

# Regex: U+FFFD as single missing vowel in common Vietnamese syllables
REGEX_FIXES: list[tuple[str, str]] = [
    (r"nh\ufffdn vi\ufffdn", "nhân viên"),
    (r"nh\ufffdn s\ufffd", "nhân sự"),
    (r"nh\ufffdn s\?", "nhân sự"),
    (r"li\ufffdn k\?t", "liên kết"),
    (r"Li\ufffdn k\?t", "Liên kết"),
    (r"ch\?m c\ufffdng", "chấm công"),
    (r"m\ufffdy ch\?m c\ufffdng", "máy chấm công"),
    (r"m\ufffdy", "máy"),
    (r"M\ufffdy", "Máy"),
    (r"Kh\ufffdng", "Không"),
    (r"kh\ufffdng", "không"),
    (r"\ufffdang", "Đang"),
    (r"Th\ufffdm", "Thêm"),
    (r"th\ufffdm", "thêm"),
    (r"X\ufffda", "Xóa"),
    (r"x\ufffda", "xóa"),
    (r"Qu\?n l\ufffd", "Quản lý"),
    (r"Qu\?n l", "Quản l"),
    (r"v\ufffdn tay", "vân tay"),
    (r"khu\ufffdn m\?t", "khuôn mặt"),
    (r"khu\ufffdn m\ufffdt", "khuôn mặt"),
    (r"Ch\ufffda c\ufffd", "Chưa có"),
    (r"ch\ufffda c\ufffd", "chưa có"),
    (r"thi\ufffdt b\?", "thiết bị"),
    (r"Thi\ufffdt b\?", "Thiết bị"),
    (r"thi\ufffdt b\ufffd", "thiết bị"),
    (r"d\ufffd li\?u", "dữ liệu"),
    (r"d\ufffd li\ufffdu", "dữ liệu"),
    (r"t\ufffdi", "tải"),
    (r"T\ufffdi", "Tải"),
    (r"l\ufffdnh", "lệnh"),
    (r"L\ufffdnh", "Lệnh"),
    (r"g\?i", "gửi"),
    (r"G\?i", "Gửi"),
    (r"k\?t n\?i", "kết nối"),
    (r"du\?c", "được"),
    (r"Ch\ufffda", "Chưa"),
    (r"ch\ufffda", "chưa"),
    (r"ngu\?i d\ufffdng", "người dùng"),
    (r"Ngu\?i d\ufffdng", "Người dùng"),
    (r"Qu\?n tr\? vi\ufffdn", "Quản trị viên"),
    (r"danh s\ufffdch", "danh sách"),
    (r"chi nh\ufffdnh", "chi nhánh"),
    (r"t\ufffdng quan", "tổng quan"),
    (r"T\ufffdng quan", "Tổng quan"),
    (r"b\? l\?c", "bộ lọc"),
    (r"B\? l\?c", "Bộ lọc"),
    (r"hi\?n th\?", "hiển thị"),
    (r"Hi\?n th\?", "Hiển thị"),
    (r"t\? kh\?a", "từ khóa"),
    (r"ho\?c", "hoặc"),
    (r"tr\?c", "trước"),
    (r"tru\?c", "trước"),
    (r"th\?t b\?i", "thất bại"),
    (r"xu\?t", "xuất"),
    (r"xu\?ng", "xuống"),
    (r"ch\?n", "chọn"),
    (r"Ch\?n", "Chọn"),
    (r"Vui l\ufffdng", "Vui lòng"),
    (r"d\? ", "để "),
    (r"D\? ", "Để "),
    (r"h\? so", "hồ sơ"),
    (r"H\? so", "Hồ sơ"),
    (r"Th\?nh c\ufffdng", "Thành công"),
    (r"th\?nh c\ufffdng", "thành công"),
    (r"tr\ufffdn ", "trên "),
    (r"c\ufffdc ", "các "),
    (r"c\ufffd ", "có "),
    (r"d\ufffd ", "đã "),
    (r"đ\ufffd ", "để "),
    (r"t\ufffd ", "từ "),
    (r"l\ufffdc", "lọc"),
    (r"L\ufffdc", "Lọc"),
    (r"cu\?n", "cuộn"),
    (r"m\ufffdn h\ufffdnh", "màn hình"),
    (r"th\ufffdp", "thấp"),
    (r"b\?m", "bấm"),
    (r"Tr\ufffdnh", "Tránh"),
    (r"Ng\ufffdn", "Ngón"),
    (r"ph\ufffdi", "phải"),
    (r"tr\ufffdi", "trái"),
    (r"gi\ufffda", "giữa"),
    (r"\ufffdp \ufffdt", "áp út"),
    (r"\ufffdt", "út"),
    (r"c\ufffdi", "cái"),
    (r"Nh\ufffdp", "Nhập"),
    (r"nh\ufffdp", "nhập"),
    (r"t\ufffd \ufffdd\ufffdng", "tự động"),
    (r"sinh t\ufffdn", "sinh tên"),
    (r"Kh\ufffdng th\ufffd", "Không thể"),
    (r"t\ufffdo", "tạo"),
    (r"L\ufffdi", "Lỗi"),
    (r"l\ufffdi", "lỗi"),
    (r"ki\?m tra", "kiểm tra"),
    (r"Ki\?m tra", "Kiểm tra"),
    (r"g\ufffdi", "gửi"),
    (r"G\ufffdi", "Gửi"),
    (r"\ufffd\ufffd g\ufffdi", "Đã gửi"),
    (r"\ufffd\ufffd t\ufffdi", "Đã tải"),
    (r"\ufffd\ufffd", "Đã"),
    (r"Đ\ufffdi", "Đổi"),
    (r"đ\ufffdi", "đổi"),
    (r"G\ufffdn", "Gán"),
    (r"g\ufffdn", "gán"),
    (r"v\?i", "với"),
    (r"V\?i", "Với"),
    (r"h\? th\?ng", "hệ thống"),
    (r"H\? th\?ng", "Hệ thống"),
    (r"S\?a", "Sửa"),
    (r"s\?a", "sửa"),
    (r"t\ufffdn", "tên"),
    (r"T\ufffdn", "Tên"),
    (r"m\ufffd th\ufffd", "mã thẻ"),
    (r"M\ufffd th\ufffd", "Mã thẻ"),
    (r"m\? th\?", "mã thẻ"),
    (r"M\? th\?", "Mã thẻ"),
    (r"m\?t kh\?u", "mật khẩu"),
    (r"M\?t kh\?u", "Mật khẩu"),
    (r"quy\?n", "quyền"),
    (r"Quy\?n", "Quyền"),
    (r"d\?u", "dấu"),
    (r"D\?u", "Dấu"),
    (r"Thi\?t l\?p", "Thiết lập"),
    (r"thi\?t l\?p", "thiết lập"),
    (r"luong", "lương"),
    (r"L\?p", "Lập"),
    (r"l\?p", "lập"),
    (r"ph\? c\?p", "phụ cấp"),
    (r"ph\ufffd c\?p", "phụ cấp"),
    (r"danh m\?c", "danh mục"),
    (r"danh m\ufffdc", "danh mục"),
    (r"thu\?t to\?n", "thuật toán"),
    (r"thu\ufffdt to\?n", "thuật toán"),
    (r"m\?n", "màn"),
    (r"c\?ng th\?c", "công thức"),
    (r"Luong ca c\? \ufffdd\?nh", "Lương ca cố định"),
    (r"Luong ca", "Lương ca"),
    (r"\ufffd\?c", "Đọc"),
    (r"đ\?c", "đọc"),
    (r"B\? l\?c t\ufffdng quan", "Bộ lọc tổng quan"),
    (r"user d\ufffd", "user đã"),
    (r"user d\?", "user đã"),
    (r" · ", " · "),
]

LITERAL_QUESTION = [
    ("Thiết bị", "Thi?t b?"),
    ("mã thẻ", "m? th?"),
    ("Mã thẻ", "M? th?"),
    ("mật khẩu", "m?t kh?u"),
    ("Mật khẩu", "M?t kh?u"),
    ("quyền", "quy?n"),
    ("Sửa", "S?a"),
    ("Quản", "Qu?n"),
    ("kết", "k?t"),
    ("để", "d?"),
    ("Để", "D?"),
    ("từ", "t?"),
    ("Từ", "T?"),
    ("mặt", "m?t"),
    ("sự", "s?"),
    ("chấm", "ch?m"),
    ("công", "c?ng"),
    ("chọn", "ch?n"),
    ("Chọn", "Ch?n"),
    ("tải", "t?i"),
    ("Tải", "T?i"),
    ("lỗi", "l?i"),
    ("Lỗi", "L?i"),
    ("gửi", "g?i"),
    ("Gửi", "G?i"),
    ("được", "du?c"),
    ("thẻ", "th?"),
    ("Thẻ", "Th?"),
    ("thử", "th?"),
    ("Thử", "Th?"),
    ("bộ", "b?"),
    ("Bộ", "B?"),
    ("lọc", "l?c"),
    ("Lọc", "L?c"),
    ("hiển thị", "hi?n th?"),
    ("Hiển thị", "Hi?n th?"),
    ("từ khóa", "t? kh?a"),
    ("hoặc", "ho?c"),
    ("trước", "tru?c"),
    ("thất bại", "th?t b?i"),
    ("xuất", "xu?t"),
    ("xuống", "xu?ng"),
    ("người", "ngu?i"),
    ("Người", "Ngu?i"),
    ("quản trị", "qu?n tr?"),
    ("Quản trị", "Qu?n tr?"),
    ("kiểm tra", "ki?m tra"),
    ("Kiểm tra", "Ki?m tra"),
    ("bấm", "b?m"),
    ("cuộn", "cu?n"),
    ("hồ sơ", "h? so"),
    ("Hồ sơ", "H? so"),
    ("thiết lập", "thi?t l?p"),
    ("Thiết lập", "Thi?t l?p"),
    ("phụ cấp", "ph? c?p"),
    ("danh mục", "danh m?c"),
    ("thuật toán", "thu?t to?n"),
    ("màn", "m?n"),
    ("công thức", "c?ng th?c"),
    ("đọc", "d?c"),
    ("Đọc", "D?c"),
]

COMMENT_FIXES = [
    ("/// Bộ lọc từ chip tổng quan (Tổng user / Đã liên kết / Chưa liên kết / TB online).", "/// B? l?c t? chip t?ng quan (T?ng user /  lin k?t / Chua lin k?t / TB online)."),
    ("/// Bộ lọc danh sách nhân viên khi gán/liên kết user máy chấm công.", "/// B? l?c danh sch nhn vin khi gn/lin k?t user my ch?m cng."),
    ("// Load devices first - dùng getDevices(storeOnly: true) để lấy thiết bị trong store", "// Load devices first - dng getDevices(storeOnly: true) d? l?y thi?t b? trong store"),
    ("// Ham chuyen doi tieng Viet co dau sang khong dau", "// Ham chuyen doi tieng Viet co dau sang khong dau"),
]


def fix_file(path: Path) -> int:
    if not path.exists():
        return 0
    text = path.read_text(encoding="utf-8")
    original = text
    before_fffd = text.count("\ufffd")

    for bad, good in COMMENT_FIXES:
        text = text.replace(bad, good) if bad != good else text

    for bad, good in sorted(LITERAL_QUESTION, key=lambda x: -len(x[1])):
        # Only replace in strings/comments — safe global for these files
        text = text.replace(good, bad)

    for pattern, repl in REGEX_FIXES:
        text = re.sub(pattern, repl, text)

    for bad, good in REPLACEMENTS:
        if bad != good:
            text = text.replace(bad, good)

    # Mojibake line recovery
    lines_out = []
    for line in text.split("\n"):
        if "\ufffd" in line or "Ã" in line:
            try:
                recovered = line.encode("latin-1").decode("utf-8")
                if recovered.count("\ufffd") < line.count("\ufffd"):
                    line = recovered
            except (UnicodeDecodeError, UnicodeEncodeError):
                pass
        lines_out.append(line)
    text = "\n".join(lines_out)

    after_fffd = text.count("\ufffd")
    if text != original:
        path.write_text(text, encoding="utf-8")
    print(f"{path.relative_to(ROOT)}: U+FFFD {before_fffd} -> {after_fffd}")
    return before_fffd - after_fffd


def main():
    total = 0
    for p in TARGETS:
        total += fix_file(p)

    # Report remaining
    for p in TARGETS:
        if p.exists():
            t = p.read_text(encoding="utf-8")
            if "\ufffd" in t:
                print(f"  WARN remaining U+FFFD in {p.name}: {t.count(chr(0xFFFD))}")
                for i, line in enumerate(t.split("\n"), 1):
                    if "\ufffd" in line and "?" not in line[:5]:
                        print(f"    L{i}: {line.strip()[:100]}")
    print(f"Fixed approx {total} replacement chars")


if __name__ == "__main__":
    main()
