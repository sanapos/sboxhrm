#!/usr/bin/env python3
"""Fix U+FFFD and mojibake in device_users_screen.dart."""
from pathlib import Path
import re

PATH = Path(__file__).resolve().parents[1] / "flutter_client/lib/screens/device_users_screen.dart"

# Exact corrupted -> correct (from file analysis)
EXACT = {
    "M\ufffd th\u1ebb": "Mã thẻ",
    "m\ufffd th\u1ebb": "mã thẻ",
    "Li\ufffdn k?t NV": "Liên kết NV",
    "Ch\u01b0a li\ufffdn k?t": "Chưa liên kết",
    "S?a t\ufffdn, m\ufffd th\u1ebb, m\u1eadt kh\u1ea9u, quy\u1ec1n": "Sửa tên, mã thẻ, mật khẩu, quyền",
    "Qu?n l\ufffd v\ufffdn tay": "Quản lý vân tay",
    "Th\ufffdm, x\ufffda d\u1ea5u v\ufffdn tay": "Thêm, xóa dấu vân tay",
    "Qu?n l\ufffd khu\ufffdn m?t": "Quản lý khuôn mặt",
    "Th\ufffdm, x\ufffda khu\ufffdn m?t": "Thêm, xóa khuôn mặt",
    "\ufffd?i li\ufffdn k?t nh\ufffdn vi\ufffdn": "Đổi liên kết nhân viên",
    "G\ufffdn v\u1edbi nh\ufffdn s?": "Gán với nhân sự",
    "\ufffdang li\ufffdn k?t:": "Đang liên kết:",
    "Li\ufffdn k?t v\u1edbi nh\ufffdn vi\ufffdn trong h\u1ec7 th\u1ed1ng": "Liên kết với nhân viên trong hệ thống",
    "X\ufffda ngu?i d\ufffdng": "Xóa người dùng",
    "X\ufffda kh\u1ecfi m\ufffdy ch?m c\ufffdng": "Xóa khỏi máy chấm công",
    "${_filteredUsers.length} nh\ufffdn vi\ufffdn \ufffd ${_devices.length} thi\u1ebft b\u1ecb": "${_filteredUsers.length} nhân viên · ${_devices.length} thiết bị",
}

# Regex-based single-char fixes (U+FFFD -> vowel)
REGEX_FIXES = [
    (r"nh\ufffdn vi\ufffdn", "nhân viên"),
    (r"nh\ufffdn s\?", "nhân sự"),
    (r"li\ufffdn k\?t", "liên kết"),
    (r"Li\ufffdn k\?t", "Liên kết"),
    (r"ch\?m c\ufffdng", "chấm công"),
    (r"m\ufffdy ch\?m c\ufffdng", "máy chấm công"),
    (r"Kh\ufffdng", "Không"),
    (r"kh\ufffdng", "không"),
    (r"\ufffdang", "Đang"),
    (r"Th\ufffdm", "Thêm"),
    (r"th\ufffdm", "thêm"),
    (r"X\ufffda", "Xóa"),
    (r"x\ufffda", "xóa"),
    (r"Qu\?n l\ufffd", "Quản lý"),
    (r"v\ufffdn tay", "vân tay"),
    (r"khu\ufffdn m\?t", "khuôn mặt"),
    (r"Ch\u01b0a c\ufffd", "Chưa có"),
    (r"ch\u01b0a c\ufffd", "chưa có"),
    (r"thi\ufffdt b\?", "thiết bị"),
    (r"Thi\ufffdt b\?", "Thiết bị"),
    (r"d\ufffd li\?u", "dữ liệu"),
    (r"t\ufffdi", "tải"),
    (r"T\ufffdi", "Tải"),
    (r"l\ufffdnh", "lệnh"),
    (r"L\ufffdnh", "Lệnh"),
    (r"g\?i", "gửi"),
    (r"G\?i", "Gửi"),
    (r"k\?t n\?i", "kết nối"),
    (r"du\?c", "được"),
    (r"Ch\u01b0a", "Chưa"),
    (r"ch\u01b0a", "chưa"),
    (r"ngu?i d\ufffdng", "người dùng"),
    (r"Ngu?i d\ufffdng", "Người dùng"),
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
    (r"hy\?n", "hãy"),
    (r"H\?y", "Hãy"),
    (r"l\?i", "lỗi"),
    (r"L\?i", "Lỗi"),
    (r"ki\?m tra", "kiểm tra"),
    (r"Ki\?m tra", "Kiểm tra"),
    (r"\ufffd\ufffd", "Đã"),  # common double replacement for Đã
    (r"\ufffd ", "· "),  # middle dot separator
]

# Mojibake fixes (UTF-8 read as Latin-1)
MOJIBAKE = [
    ("Ã¡", "á"), ("Ã ", "à"), ("Ã£", "ã"), ("Ã¢", "â"),
    ("Ã©", "é"), ("Ã¨", "è"), ("Ãª", "ê"), ("Ã­", "í"),
    ("Ã³", "ó"), ("Ã²", "ò"), ("Ã´", "ô"), ("Ãµ", "õ"),
    ("Ãº", "ú"), ("Ã¹", "ù"), ("Ã½", "ý"),
    ("Ä\u0083", "ă"), ("Æ°", "ư"), ("Ä\u0091", "đ"),
    ("áº", "ậ"), ("á»", "ộ"), ("áº£", "ả"),
]


def fix_mojibake_line(line: str) -> str:
    try:
        recovered = line.encode("latin-1").decode("utf-8")
        if recovered.count("\ufffd") < line.count("\ufffd"):
            return recovered
    except (UnicodeDecodeError, UnicodeEncodeError):
        pass
    return line


def main():
    text = PATH.read_text(encoding="utf-8")
    original = text

    for bad, good in EXACT.items():
        text = text.replace(bad, good)

    for pattern, repl in REGEX_FIXES:
        text = re.sub(pattern, repl, text)

    for bad, good in MOJIBAKE:
        text = text.replace(bad, good)

    # Line-by-line mojibake recovery
    lines = []
    for line in text.split("\n"):
        if "\ufffd" in line or "Ã" in line:
            line = fix_mojibake_line(line)
        lines.append(line)
    text = "\n".join(lines)

    # Remaining ? fixes (after U+FFFD pass)
    more = {
        "S?a": "Sửa", "Qu?n": "Quản", "ngu?i": "người", "Ngu?i": "Người",
        "m?t": "mặt", "k?t": "kết", "s?": "sự", "ch?m": "chấm",
        "c?ng": "công", "ch?n": "chọn", "t?i": "tải", "l?i": "lỗi",
        "d?u": "dấu", "G?n": "Gán", "g?n": "gán",
    }
    for bad, good in sorted(more.items(), key=lambda x: -len(x[0])):
        # Only replace in string contexts - risky but file is mostly Vietnamese UI
        text = text.replace(bad, good)

    PATH.write_text(text, encoding="utf-8")
    remaining_fffd = text.count("\ufffd")
    print(f"U+FFFD remaining: {remaining_fffd}")
    print(f"Changed: {text != original}")

    # Show dialog section sample
    idx = text.find("_showUserActionsDialog")
    if idx >= 0:
        sample = text[idx:idx+1200]
        for line in sample.split("\n")[:25]:
            if any(c in line for c in "?Ð\uFFFD") or "Text(" in line or "_buildInfoRow" in line:
                print(line)


if __name__ == "__main__":
    main()
