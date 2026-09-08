#!/usr/bin/env python3
"""Fix erroneous replacements from prior encoding pass."""
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "flutter_client/lib/screens/device_users_screen.dart"

FIXES = [
    ("Sửa t\ufffdn", "Sửa tên"),
    ("Chọn m\ufffdy", "Chọn máy"),
    ("tự m\ufffdy", "từ máy"),
    ("Tải h? so", "Tải hồ sơ"),
    ("xuống m\ufffdy", "xuống máy"),
    ("Nh\ufffdn vi\ufffdn tải", "Nhân viên tải"),
    ("Đãng", "Đóng"),
    ("Không c· user d· liên kết", "Không có user đã liên kết"),
    ("m\ufffdy chấm công với h? so", "máy chấm công với hồ sơ"),
    ("Không c· user chưa", "Không có user chưa"),
    ("tr\ufffdn m\ufffdy d· được", "trên máy đã được"),
    ("Không c· user tr\ufffdn", "Không có user trên"),
    ("tr\ufffdn c\ufffdc m\ufffdy", "trên các máy"),
    ("đồng bộ tự nhân viên", "đồng bộ từ nhân viên"),
    ("Th\ufffdnh c\ufffdng", "Thành công"),
    ("nh\ufffdn vi\ufffdn ·", "nhân viên ·"),
    ("c· ", "có "),
    ("d· ", "đã "),
    ("tr\ufffdn ", "trên "),
    ("c\ufffdc ", "các "),
    ("m\ufffdy", "máy"),
    ("h? so", "hồ sơ"),
    ("B\ufffd l\ufffdc", "Bộ lọc"),
    ("T\ufffdng quan", "Tổng quan"),
    ("Đang l\ufffdc", "Đang lọc"),
    ("Ch\ufffdn ", "Chọn "),
    ("ch\ufffdn ", "chọn "),
    ("Vui l\ufffdng", "Vui lòng"),
    ("kh\ufffdng cu\?n", "không cuộn"),
    ("m\ufffdn h\ufffdnh", "màn hình"),
    ("th\ufffdp", "thấp"),
    ("b\ufffdm", "bấm"),
    ("Tr\ufffdnh", "Tránh"),
    ("Qu\ufffdn tr\ufffd vi\ufffdn", "Quản trị viên"),
    ("Ngu\ufffdi d\ufffdng", "Người dùng"),
    ("Ngón c\ufffdi", "Ngón cái"),
    ("Ngón tr\ufffd", "Ngón trỏ"),
    ("Ngón gi\ufffda", "Ngón giữa"),
    ("Ngón \ufffdp \ufffdt", "Ngón áp út"),
    ("Ngón \ufffdt", "Ngón út"),
    ("tay tr\ufffdi", "tay trái"),
    ("tay ph\ufffdi", "tay phải"),
    ("kh\ufffdng d\ufffdu", "không dấu"),
    ("c\ufffd d\ufffdu", "có dấu"),
    ("b\ufffdn d\ufffdu\?i", "bên dưới"),
    ("Nh\ufffdp", "Nhập"),
    ("t\ufffd \ufffdd\ufffdng", "tự động"),
    ("sinh t\ufffdn", "sinh tên"),
    ("Kh\ufffdng th\ufffd", "Không thể"),
    ("t\ufffdo file", "tạo file"),
    ("xu\ufffdt Excel", "xuất Excel"),
    ("L\ufffdi xu\ufffdt", "Lỗi xuất"),
    ("Kh\ufffdng c\ufffd d\ufffd li\ufffdu", "Không có dữ liệu"),
    ("xu\ufffdt", "xuất"),
    ("hi\ufffdn th\ufffd", "hiển thị"),
    ("Hi\ufffdn th\ufffd", "Hiển thị"),
    ("chi nh\ufffdnh", "chi nhánh"),
    ("Ch\ufffda c\ufffd", "Chưa có"),
    ("ch\ufffda c\ufffd", "chưa có"),
    ("k\ufffdt n\ufffdi", "kết nối"),
    ("H\ufffdy k\ufffdt n\ufffdi", "Hãy kết nối"),
    ("tru\ufffdc", "trước"),
    ("th\ufffd kh\ufffda", "từ khóa"),
    ("Th\ufffd", "Thử"),
    ("l\ufffdc t\ufffdng quan", "lọc tổng quan"),
    ("d\ufffdng b\ufffd", "đồng bộ"),
    ("ho\ufffdc", "hoặc"),
    ("th\ufffdt b\ufffdi", "thất bại"),
    ("g\ufffdi l\ufffdnh", "gửi lệnh"),
    ("ch\ufffda th\ufffdy", "chưa thấy"),
    ("Refresh n\ufffdu", "Refresh nếu"),
    ("l\ufffdnh \ufffdd\ufffd g\ufffdi", "lệnh đã gửi"),
    ("Nh\ufffdn Refresh", "Nhấn Refresh"),
    ("\ufffdang g\ufffdi", "Đang gửi"),
    ("\ufffd\ufffd g\ufffdi", "Đã gửi"),
    ("\ufffd\ufffd t\ufffdi", "Đã tải"),
    ("· ", "· "),  # keep middle dot
]

def main():
    text = PATH.read_text(encoding="utf-8")
    original = text
    for bad, good in FIXES:
        text = text.replace(bad, good)
    PATH.write_text(text, encoding="utf-8")
    print("U+FFFD:", text.count("\ufffd"))
    print("changed:", text != original)

if __name__ == "__main__":
    main()
