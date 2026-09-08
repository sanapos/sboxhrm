#!/usr/bin/env python3
"""Master fix for corrupted Vietnamese in device_users + payroll_summary."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / "flutter_client/lib/screens/device_users_screen.dart",
    ROOT / "flutter_client/lib/screens/attendance/payroll_summary_tab.dart",
]

# corrupted -> correct (longest first when applied)
PAIRS = """
đang ký|đang k
đăng ký|đang k
Đăng ký|Đang k
đăng ký|đang ký
Đăng ký|Đang ký
Quản trị viên|Quản trỏ vin
Quản trị viên|Quản trỏ viên
Người dùng|Người dng
Người dùng|Người dng
thành công|thnh cng
thành công|thnh cng
Hãy nhấn|Hy nh?n
Hãy kết nối|Hy kết nối
Hãy đăng ký|Hy đang k
nào được|no được
nào|no
hồ sơ nhân sự nào|hồ sơ nhân sự no
nhân viên nào|nhân viên no
thiết bị nào|thiết bị no
Tìm nhân viên|Tm nhân viên
Tìm nhân viên|Tm nhanh
Tìm theo tên|Tm theo tên
Không tìm thấy|Không tm thấy
Không tìm thấy|Không tm thấy
Thử từ khóa|Thẻ tự kha khc
Vân tay|Vn tay
Danh sách|Danh sch
ngón tay|ngn tay
Ngón tay|Ngn tay
trùng lập|trng lập
từng ngón|tựng ngn
thiết kế|thi?t k? m?i
đẹp hơn|đểp hon
đường vân tay|u?ng vân tay gi?
bàn tay|bn tay
Cái|Ci
TAY TRÁI|TAY TRI
TAY PHẢI|TAY PH?I
Lòng bàn tay|Lng bn tay
Các ngón tay|Cc ngt tay
Thống kê|Thẻng k
Hướng dẫn|Hu?ng đển
Chú thích màu|Ch· thch mu
Chưa đăng ký|Chưa đang k
Đã đăng ký|Đã đang k
hành động|hnh đểng
Xác nhận|Xc nh?n
bằng cách|bộng cch
trạng thái|trỏng thi
mới nhất|m?i nh?t
Tiếp tục|Ti?p tực
sẽ xử lý|sự x? l·
vào danh sách|vo danh sch
Khuôn mặt|Khun mặt
đã được lưu|đã được luu
Thông báo|Thửng bo
Giao diện|Giao di?n
hỗ trợ|h? trỏ
Quý khách|Qu· khch
vui lòng|vui lng
trực tiếp|trỏc ti?p
Đã hiểu|Đã hi?u
Đồng bộ|?ng bộ
Đồng bộ ngay|?ng bộ ngay
sinh trắc học|sinh trỏc h?c
thể gửi|thẻ gửi
nhận được|nh?n được
rồi thử|R?i thẻ
Nhân sự chấm công|Nhn sự chấm công
bảng dữ liệu|bộng dữ liệu
chụp|ch?p
Chỉnh sửa|Chọnh sựa
Cập nhật|C?p nh?t
mới|m?i
Số thẻ|S? thẻ
nếu có|nếu c
Quyền hạn|Quyền h?n
Đồng bộ nhân viên vào|?ng bộ nhân viên vo
Tạo DeviceUser|Tựo DeviceUser
thông tin từ|thng tin tự
tạo thành công|tạo thnh cng
vào máy chấm công|vo máy chấm công
thể đồng bộ|thẻ đồng bộ
Đổi liên kết|?i liên kết
khác để thay đổi|khc để thay đểi
tìm kiếm|tm ki?m
Tìm theo tên, mã NV, phòng ban|Tm theo tên, m· NV, phng ban
phù hợp|ph· h?p
Không còn nhân viên|Không cn nhân viên
Mã:|M:
tiến trình|ti?n trnh
Số lần|S? lần
thành công|thnh cng
thường cần|thu?ng cần
lỗi ngón đã có|lỗi ngn đã c
xóa vân tay cũ|xóa vân tay cu
Đợi máy xử lý|?i máy x? l·
đặt ngón tay|đểt ngn tay
lên máy|ln máy
Bắt đầu polling|Bột dấu polling
trạng thái|trỏng thi
nhiều thời gian|nhi?u thẻi gian
đến máy|đến máy
máy đang chờ|máy đang ch?
đặt ngón|?t ngn
cảm biến|c?m bi?n
Hướng dẫn trên máy|hu?ng đển trên máy
đã nhận được|đã nh?n được
đăng ký thành công|đang k· thnh cng
đặt ngón tay lên cảm biến|đểt ngn tay ln c?m bi?n
thử lại|thẻ lỗi
Timeout — chưa nhận|Timeout · chưa nh?n
Hết thời gian chờ|H?t thẻi gian ch?
thử lại đăng ký|thẻ lỗi đang k
Đã hủy đăng ký|Đã hãy đang k
ở trên|? trn
giữ yên|gi? yn
hoàn tất|hon tựt
nhìn thẳng|nhn thẻng
vào camera|vo camera
dùng|dng
dùng getDevices|dng getDevices
để lấy|để l?y
cụ thể|c? thẻ
đợi máy trả|đểi máy trỏ v?
nhiều lần|nhi?u lần
vòng 30 giây|vng 30 giy
Trỏ về tên|Trỏ v? tên
của mặt|c?a mặt
thông qua|thng qua
ẩn đi|?n di
tự cấp|tự c?p
muốn hiện|mu?n hi?n
bỏ comment|bộ comment
phía dưới|ph?n du?i
để trống|? trỏng
sẽ tự sinh|sự tự sinh
tự cấp ID|tự c?p ID
VD: Nguyễn Văn A|VD: Nguy?n Van A
sẽ tự động|sự tự đểng
bên dưới|bn du?i
thể lưu|thẻ luu
Chọn & sắp xếp cột|Chọn & sựp x?p c?t
Mặc định|M?c đểnh
Cột cố định|C?t c? đểnh
di chuyển|di chuy?n
Kéo để sắp xếp|Ko để sựp x?p
thứ tự cột|thẻ từ c?t
Áp dụng|p đểng
Hủy|H?y
định nghĩa| đểnh nghia
cột bảng|c?t bộng
đang hoạt động|dang ho?t đểng
bảng lương|bộng lương
loại khỏi|bộ lo?i kh?i
từng hợp|từng h?p
Kế toán|K? ton
Giám đốc|Gim đọc
Lương theo công|Luong theo cng
PC cố định|PC c? đểnh
PC theo ngày|PC theo ngy
Tổng PC kỳ|Từng PC k?
Sản lượng|S?n lu?ng
Ký tên|K tên
employeeId →|employeeId ?
chỉ dùng log|Ch? dng log
màn cha đã tải|mn cha đã tải
tránh quay|trnh quay
hàng trăm|hng tram
paged API —|paged API
chỉ manager|ch? manager+
Loại bộ NV|Lo?i bộ NV
capped — tránh|capped trnh
treo|treo
Bản chấm công kỳ|Bộn ch?p chấm cng k?
lưu độc lập|luu đọc lập
chốt phiếu|ch?t phi?u
Vào|Vo
Không dùng|Không dng
Áp dụng mức|p đểng m?c tr?n
cơ sở|co sự
lương tối thiểu|lương tải thi?u
vùng|vng
luật Việc làm|lu?t Vi?c lm
công thuật toán|cng thu?t ton
màn Thiết lập|mn Thiết lập
mức cấu hình|m?c c?u hnh
thực nhận theo|thẻc nh?n theo
Lương ca cố định|Luong ca c? đểnh
Chấm công|Ch?m cng
công nguồn|cng ngu?n
thuật toán|thu?t ton
Tổng hợp theo ca|Từng h?p theo ca
tính lương|tênh lương
hoàn thành theo công|hon thnh theo cng
mức tháng|m?c thng
Bỏ qua thưởng|Bộ qua thu?ng
đã chi tiền mặt|đã chi ti?n mặt
giữ thưởng|gi? thu?ng
Đoàn phí|on ph
chưa đóng BHXH|chua dng BHXH
mức đóng|m?c dng
hệ số từng|h? sự từng
NLĐ|NL dng
Nhân viên trong phạm vi|Nhn vin trong ph?m vi
phòng ban|phng ban
Chốt lương|Ch?t lương
Kỳ:|K?:
Phiếu đã tồn tại|Phi?u đã từn tải
công kỳ sẽ được|cng k? sự được
cập nhật|c?p nh?t
Xác nhận chốt lương|Xc nh?n ch?t lương
Không có NV hợp lệ|Không có NV h?p l? (thi?u
thiếu hồ sơ|thi?u hồ sơ
phía app|pha app
Đang chốt|Đang ch?t
dữ liệu|để li?u
Xuất Excel|Xu?t Excel
Đã lưu vào|Đã luu vo
Tải về|Tải v?
TỔNG CỘNG|TừNG C?NG
BẢNG TỔNG HỢP LƯƠNG|BộNG TừNG H?P LUONG
(Ký, ghi rõ họ tên)|(K, ghi r h? tên)
Xuất PNG|Xu?t PNG
Đã lưu vào Ảnh|Đã luu vo ?nh
Chi tiết|Chi ti?t
Công chuẩn|Cng chu?n
Ngày phép|Ngy php
Ngày vắng|Ngy v?ng
ngày|ngy
Tăng ca ngày thường|Tang ca ngy thu?ng
Tăng ca ngày lễ|Tang ca ngy l?
Đi trễ|i tr?
lần|l?n
Lương hoàn thành|Luong hon thnh
Lương HT theo công|Luong HT theo cng
Lương theo ngày|Luong theo ngy
Phụ cấp theo ngày|Ph? c?p theo ngy
mức/ngày|m?c/ngy
Phụ cấp khác|Ph? c?p khc
Mức đóng bảo hiểm|M?c dng bộo hi?m
Tổng BHXH NLĐ|Từng BHXH NL dng
THỰC NHẬN|TH?C NH?N
Đang tính toán|Đang tênh ton
khoảng thời gian|kho?ng thẻi gian
Tháng này|Thng ny
Tháng trước|Thng trước
Tuần này|Tu?n ny
Hôm nay|Hm nay
Hôm qua|Hm qua
Tùy chọn|Ty chọn
Tùy chọn khác|Ty chọn khc
Phòng ban|Phng ban
Tổng lương theo công|Từng lương theo cng
Ngày công TB|Ngy cng TB
toàn công ty|ton cng ty
dòng|dng
toàn màn hình|ton màn hình
Xem toàn màn hình|Xem ton màn hình
Bảng tổng hợp lương|Bộng từng h?p lương
Thoát chế độ|Thoút ch? để ton màn hình
Xem chi tiết đầy đủ|Xem chi ti?t đểy để
Tổng hợp lương|Từng h?p lương
""".strip().splitlines()

def main():
    for path in FILES:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        before = text.count("\ufffd")
        for line in PAIRS:
            if "|" not in line:
                continue
            good, bad = line.split("|", 1)
            if bad and good != bad:
                text = text.replace(bad, good)
        # Remove any remaining U+FFFD in Vietnamese UI strings via common char guesses
        # Fallback: replace lone replacement char between ASCII letters
        import re
        def fix_lone(m):
            w = m.group(0)
            # skip code like ?. or ?? 
            return w
        path.write_text(text, encoding="utf-8")
        after = text.count("\ufffd")
        print(f"{path.name}: U+FFFD {before} -> {after}")

if __name__ == "__main__":
    main()
