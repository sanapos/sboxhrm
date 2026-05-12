#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re

f = r'e:\Flutter\ZKTecoADMS-master\ZKTecoADMS-master\flutter_client\lib\screens\system_admin\landing_content_tab.dart'

with open(f, 'r', encoding='utf-8') as fp:
    s = fp.read()

R = '\ufffd'  # U+FFFD replacement char

replacements = [
    # Tab labels
    (f"Hero & Li{R}n h?", "Hero & Liên hệ"),
    (f"T{R}nh nang", "Tính năng"),
    (f"G{R}i d?ch v?", "Gói dịch vụ"),
    ("Hu?ng d?n", "Hướng dẫn"),
    ("S?n ph?m", "Sản phẩm"),

    # Labels map
    (f"Ti{R}u d? Hero", "Tiêu đề Hero"),
    (f"M{R} t? Hero", "Mô tả Hero"),
    ("S? di?n tho?i / Hotline", "Số điện thoại / Hotline"),
    ("S? Zalo (ho?c link zalo.me/...)", "Số Zalo (hoặc link zalo.me/...)"),
    (f"Email li{R}n h?", "Email liên hệ"),
    (f"{R}?a ch?", "Địa chỉ"),

    # Hero section messages
    (f"{R}{R} luu n?i dung Hero & Li{R}n h?!", "Đã lưu nội dung Hero & Liên hệ!"),
    (f"Th{R}ng tin li{R}n h?", "Thông tin liên hệ"),
    (f"{R}ang luu...", "Đang lưu..."),
    ("Luu thay d?i", "Lưu thay đổi"),
    ("N?i dung hi?n th? ? ph?n d?u trang ch?", "Nội dung hiển thị ở phần đầu trang chủ"),
    ("L?i: $e", "Lỗi: $e"),

    # Features section
    (f"{R}{R} luu danh s{R}ch t{R}nh nang!", "Đã lưu danh sách tính năng!"),
    (f"Danh s{R}ch t{R}nh nang", "Danh sách tính năng"),
    (f"label: const Text('Th{R}m')", "label: const Text('Thêm')"),
    (f"Ti{R}u d? t{R}nh nang", "Tiêu đề tính năng"),
    (f"M{R} t? chi ti?t", "Mô tả chi tiết"),
    (f"Luu danh s{R}ch t{R}nh nang", "Lưu danh sách tính năng"),

    # Pricing section
    (f"{R}{R} luu b?ng gi{R}!", "Đã lưu bảng giá!"),
    (f"G{R}i d?ch v? & B?ng gi{R}", "Gói dịch vụ & Bảng giá"),
    (f"Th{R}m g{R}i", "Thêm gói"),
    (f"T{R}n g{R}i", "Tên gói"),
    (f"X{R}a g{R}i", "Xóa gói"),
    (f"Gi{R} (VD: 900.000)", "Giá (VD: 900.000)"),
    (f"{R}on v? (d/nam)", "Đơn vị (đ/năm)"),
    (f"M{R} t? g{R}i", "Mô tả gói"),
    ("N?i b?t (highlight)", "Nổi bật (highlight)"),
    (f"Li{R}n h? d? b{R}o gi{R}", "Liên hệ để báo giá"),
    (f"T{R}nh nang trong g{R}i", "Tính năng trong gói"),
    (f"Th{R}m t{R}nh nang", "Thêm tính năng"),
    (f'Chua c{R} t{R}nh nang. Nh?n "Th{R}m t{R}nh nang" d? b? sung.', 'Chưa có tính năng. Nhấn "Thêm tính năng" để bổ sung.'),
    (f"VD: T?i da 30 nh{R}n vi{R}n", "VD: Tối đa 30 nhân viên"),
    (f"tooltip: 'X{R}a'", "tooltip: 'Xóa'"),
    (f"Luu b?ng gi{R}", "Lưu bảng giá"),

    # Guide section
    (f"{R}{R} luu hu?ng d?n!", "Đã lưu hướng dẫn!"),
    (f"C{R}c bu?c hu?ng d?n", "Các bước hướng dẫn"),
    (f"Th{R}m bu?c", "Thêm bước"),
    (f"Ti{R}u d? bu?c", "Tiêu đề bước"),
    ("Luu hu?ng d?n", "Lưu hướng dẫn"),

    # Video section
    (f"{R}{R} luu c{R}i d?t video!", "Đã lưu cài đặt video!"),
    (f"Video 1 {R} Gi?i thi?u", "Video 1 – Giới thiệu"),
    (f"Video 2 {R} Hu?ng d?n", "Video 2 – Hướng dẫn"),
    (f"Ti{R}u d? video", "Tiêu đề video"),
    (f"Nh{R}n (badge)", "Nhãn (badge)"),
    ("Th?i lu?ng", "Thời lượng"),
    (f"M{R} t? ng?n", "Mô tả ngắn"),
    (f"Luu c{R}i d?t video", "Lưu cài đặt video"),
    ("URL YouTube (b?t bu?c)", "URL YouTube (bắt buộc)"),
    ("Video gi?i thi?u", "Video giới thiệu"),
    ("Video hu?ng d?n", "Video hướng dẫn"),
    ("H?c ngay", "Học ngay"),
    (f"T{R}ng quan SBOX HRM {R} ch?m c{R}ng, luong, ca l{R}m, b{R}o c{R}o",
        "Tổng quan SBOX HRM – chấm công, lương, ca làm, báo cáo"),
    (f"Thi?t l?p t? A{R}Z: k?t n?i m{R}y, th{R}m nh{R}n vi{R}n, c{R}i ca",
        "Thiết lập từ A–Z: kết nối máy, thêm nhân viên, cài ca"),

    # Products section
    (f"{R}{R} luu danh s{R}ch s?n ph?m!", "Đã lưu danh sách sản phẩm!"),
    (f"Danh s{R}ch m{R}y ch?m c{R}ng", "Danh sách máy chấm công"),
    (f"Th{R}m m{R}y", "Thêm máy"),
    ("Luu danh s?n ph?m", "Lưu sản phẩm"),
    (f"Luu danh s{R}ch s?n ph?m", "Lưu danh sách sản phẩm"),
    ("'S?n ph?m ", "'Sản phẩm "),
    (f"X{R}a s?n ph?m", "Xóa sản phẩm"),
    (f"T{R}n s?n ph?m", "Tên sản phẩm"),
    ("Thuong hi?u", "Thương hiệu"),
    (f"Gi{R} b{R}n", "Giá bán"),
    (f"Gi{R} g?c (n?u c{R})", "Giá gốc (nếu có)"),
    (f"Nh{R}n gi?m gi{R}", "Nhãn giảm giá"),
    (f"Th{R}ng s? t{R}m t?t", "Thông số tóm tắt"),
    ("URL ?nh s?n ph?m", "URL ảnh sản phẩm"),
    ("Link xem chi ti?t", "Link xem chi tiết"),

    # Default features data
    (f"Ch?m c{R}ng ZKTeco", "Chấm công ZKTeco"),
    (f"T{R}ch h?p m{R}y ch?m c{R}ng ZKTeco t? d?ng, d? li?u d?ng b? real-time qua giao th?c ADMS/PUSH.",
        "Tích hợp máy chấm công ZKTeco tự động, dữ liệu đồng bộ real-time qua giao thức ADMS/PUSH."),
    (f"Qu?n l{R} ca l{R}m vi?c", "Quản lý ca làm việc"),
    (f"T?o ca linh ho?t, xoay ca, tang ca, ngh? b{R}. H? tr? ca qua d{R}m v{R} l?ch l{R}m vi?c ph?c t?p.",
        "Tạo ca linh hoạt, xoay ca, tăng ca, nghỉ bù. Hỗ trợ ca qua đêm và lịch làm việc phức tạp."),
    (f"T{R}nh luong t? d?ng", "Tính lương tự động"),
    (f"T? d?ng t{R}nh luong theo ng{R}y c{R}ng, ph? c?p, thu?ng, kh?u tr? BHXH/thu? TNCN.",
        "Tự động tính lương theo ngày công, phụ cấp, thưởng, khấu trừ BHXH/thuế TNCN."),
    (f"Qu?n l{R} ngh? ph{R}p", "Quản lý nghỉ phép"),
    (f"Theo d{R}i ng{R}y ph{R}p, x{R}t duy?t tr?c tuy?n, t?ng h?p b{R}o c{R}o ngh? ph{R}p theo th{R}ng/nam.",
        "Theo dõi ngày phép, xét duyệt trực tuyến, tổng hợp báo cáo nghỉ phép theo tháng/năm."),
    (f"Ch?m c{R}ng ngo{R}i hi?n tru?ng", "Chấm công ngoài hiện trường"),
    (f"GPS check-in/check-out c{R} ?nh x{R}c th?c khu{R}n m?t, h? tr? nh{R}n vi{R}n field sales.",
        "GPS check-in/check-out có ảnh xác thực khuôn mặt, hỗ trợ nhân viên field sales."),
    (f"B{R}o c{R}o & Ph{R}n t{R}ch", "Báo cáo & Phân tích"),
    (f"Dashboard tr?c quan, b{R}o c{R}o chuy{R}n c?n, t?ng h?p luong, xu?t Excel t?c th{R}.",
        "Dashboard trực quan, báo cáo chuyên cần, tổng hợp lương, xuất Excel tức thì."),
    (f"Qu?n l{R} b?a an", "Quản lý bữa ăn"),
    (f"{R}ang k{R} xu?t an, theo d{R}i kh?u ph?n th?c t?, b{R}o c{R}o chi ph{R} b?a an h{R}ng ng{R}y.",
        "Đăng ký xuất ăn, theo dõi khẩu phần thực tế, báo cáo chi phí bữa ăn hàng ngày."),
    (f"Qu?n l{R} c{R}ng vi?c", "Quản lý công việc"),
    (f"Giao vi?c, theo d{R}i ti?n d?, KPI c{R} nh{R}n v{R} ph{R}ng ban theo th?i gian th?c.",
        "Giao việc, theo dõi tiến độ, KPI cá nhân và phòng ban theo thời gian thực."),
    (f"?ng d?ng Android/iOS d?y d? t{R}nh nang {R} ch?m c{R}ng, xem l?ch, ph{R} duy?t ngh? ph{R}p m?i noi.",
        "Ứng dụng Android/iOS đầy đủ tính năng – chấm công, xem lịch, phê duyệt nghỉ phép mọi nơi."),

    # Default pricing data
    (f"Mi?n ph{R}", "Miễn phí"),
    (f"Tr?i nghi?m d?y d? t{R}nh nang co b?n", "Trải nghiệm đầy đủ tính năng cơ bản"),
    (f"T?i da 10 nh{R}n vi{R}n", "Tối đa 10 nhân viên"),
    (f"Ch?m c{R}ng & b{R}o c{R}o co b?n", "Chấm công & báo cáo cơ bản"),
    ("H? tr? qua email", "Hỗ trợ qua email"),
    ("H? kinh doanh", "Hộ kinh doanh"),
    (f"D{R}nh cho h? kinh doanh & c?a h{R}ng nh?", "Dành cho hộ kinh doanh & cửa hàng nhỏ"),
    (f"T?i da 30 nh{R}n vi{R}n", "Tối đa 30 nhân viên"),
    (f"Ch?m c{R}ng & ca l{R}m vi?c", "Chấm công & ca làm việc"),
    (f"B{R}o c{R}o chi ti?t", "Báo cáo chi tiết"),
    ("H? tr? Zalo 24/7", "Hỗ trợ Zalo 24/7"),
    ("Doanh nghi?p", "Doanh nghiệp"),
    (f"Cho doanh nghi?p v?a v{R} l?n", "Cho doanh nghiệp vừa và lớn"),
    (f"Kh{R}ng gi?i h?n nh{R}n vi{R}n", "Không giới hạn nhân viên"),
    (f"{R}?y d? t{R}nh nang HRM", "Đầy đủ tính năng HRM"),
    (f"KPI & c{R}ng vi?c", "KPI & công việc"),
    (f"H? tr? uu ti{R}n 24/7", "Hỗ trợ ưu tiên 24/7"),
    (f"Nh{R} m{R}y SX", "Nhà máy SX"),
    (f"T?i uu cho nh{R} m{R}y s?n xu?t", "Tối ưu cho nhà máy sản xuất"),
    (f"Kh{R}ng gi?i h?n thi?t b?", "Không giới hạn thiết bị"),
    (f"Ch?m c{R}ng nhi?u ca / d{R}y chuy?n", "Chấm công nhiều ca / dây chuyền"),
    ("S?n lu?ng & KPI s?n xu?t", "Sản lượng & KPI sản xuất"),
    (f"T{R}ch h?p ERP/Odoo", "Tích hợp ERP/Odoo"),
    (f"B{R}o c{R}o nh{R} m{R}y chuy{R}n s{R}u", "Báo cáo nhà máy chuyên sâu"),
    ("Tri?n khai t?i ch? (on-premise)", "Triển khai tại chỗ (on-premise)"),
    (f"H? tr? k? thu?t ri{R}ng", "Hỗ trợ kỹ thuật riêng"),

    # Default guide data
    (f"{R}ang k{R} t{R}i kho?n", "Đăng ký tài khoản"),
    (f"{R}i?n th{R}ng tin doanh nghi?p, nh?n m{R} c?a h{R}ng v{R} t{R}i kho?n admin qua email trong v{R}ng 5 ph{R}t.",
        "Điền thông tin doanh nghiệp, nhận mã cửa hàng và tài khoản admin qua email trong vòng 5 phút."),
    (f"C{R}i d?t thi?t b?", "Cài đặt thiết bị"),
    (f"K?t n?i m{R}y ch?m c{R}ng ZKTeco v{R}o m?ng n?i b?, c?u h{R}nh IP server. H? tr? c{R}i d?t t? xa qua Zalo/Teamviewer.",
        "Kết nối máy chấm công ZKTeco vào mạng nội bộ, cấu hình IP server. Hỗ trợ cài đặt từ xa qua Zalo/Teamviewer."),
    (f"Th{R}m nh{R}n vi{R}n", "Thêm nhân viên"),
    (f"Nh?p danh s{R}ch nh{R}n vi{R}n, dang k{R} v{R}n tay/khu{R}n m?t. D? li?u t? d?ng d?ng b? xu?ng m{R}y ch?m c{R}ng.",
        "Nhập danh sách nhân viên, đăng ký vân tay/khuôn mặt. Dữ liệu tự động đồng bộ xuống máy chấm công."),
    (f"Thi?t l?p ca l{R}m vi?c", "Thiết lập ca làm việc"),
    (f"T?o ca l{R}m vi?c, ph{R}n ca cho nh{R}n vi{R}n/ph{R}ng ban. H? tr? ca c? d?nh, xoay ca v{R} l?ch linh ho?t.",
        "Tạo ca làm việc, phân ca cho nhân viên/phòng ban. Hỗ trợ ca cố định, xoay ca và lịch linh hoạt."),
    (f"Xem b{R}o c{R}o", "Xem báo cáo"),
    (f"B{R}o c{R}o ch?m c{R}ng, luong, ngh? ph{R}p c?p nh?t t? d?ng. Xu?t Excel/PDF ch? v?i 1 c{R} nh?p.",
        "Báo cáo chấm công, lương, nghỉ phép cập nhật tự động. Xuất Excel/PDF chỉ với 1 cú nhấp."),

    # Default products data
    (f"M{R}y ch?m c{R}ng v{R}n tay WiFi", "Máy chấm công vân tay WiFi"),
    (f"V{R}n tay {R} WiFi {R} 500 users", "Vân tay – WiFi – 500 users"),
    (f"Nh?n di?n khu{R}n m?t", "Nhận diện khuôn mặt"),
    (f"Khu{R}n m?t {R} V{R}n tay {R} Th? {R} WiFi", "Khuôn mặt – Vân tay – Thẻ – WiFi"),
    (f"M{R}y ch?m c{R}ng v{R}n tay ADMS", "Máy chấm công vân tay ADMS"),
    (f"V{R}n tay {R} Th? {R} TCP/IP {R} ADMS", "Vân tay – Thẻ – TCP/IP – ADMS"),
    (f"Nh?n di?n khu{R}n m?t ADMS", "Nhận diện khuôn mặt ADMS"),
    (f"Khu{R}n m?t {R} V{R}n tay {R} Th? {R} ADMS", "Khuôn mặt – Vân tay – Thẻ – ADMS"),
    ("Gi?m 12%", "Giảm 12%"),
    ("Gi?m 8%", "Giảm 8%"),
    ("Gi?m 16%", "Giảm 16%"),
    ("1 thi?t b? ZKTeco", "1 thiết bị ZKTeco"),
    ("2 thi?t b? ZKTeco", "2 thiết bị ZKTeco"),
    ("5 thi?t b? ZKTeco", "5 thiết bị ZKTeco"),
    ("d/nam", "đ/năm"),

    # Comments
    (f"Sub-tab 1: Hero & Li{R}n h?", "Sub-tab 1: Hero & Liên hệ"),
    (f"Sub-tab 2: T{R}nh nang", "Sub-tab 2: Tính năng"),
    (f"Sub-tab 3: G{R}i d?ch v?", "Sub-tab 3: Gói dịch vụ"),
    ("Sub-tab 4: Hu?ng d?n", "Sub-tab 4: Hướng dẫn"),
    ("Sub-tab 6: S?n ph?m", "Sub-tab 6: Sản phẩm"),
    (f"Specs Editor Dialog {R} controller ho{R}n to{R}n thu?c v? Dialog State",
        "Specs Editor Dialog – controller hoàn toàn thuộc về Dialog State"),
    (f"Keys ph?i kh?p v?i AppSettingKeys trong backend", "Keys phải khớp với AppSettingKeys trong backend"),
    (f"SuperAdmin {R} Tab qu?n l{R} n?i dung trang Landing Page c?a SBOX HRM.",
        "SuperAdmin – Tab quản lý nội dung trang Landing Page của SBOX HRM."),

    # Remaining ? strings in products card labels
    (f"M{R} t? ng?n", "Mô tả ngắn"),
    (f"Row 1: T{R}n, Thuong hi?u", "Row 1: Tên, Thương hiệu"),
    (f"Row 2: Gi{R}, Gi{R} g?c, Nh{R}n gi?m", "Row 2: Giá, Giá gốc, Nhãn giảm"),
]

count = 0
for old, new in replacements:
    if old in s:
        s = s.replace(old, new)
        count += 1

print(f"Applied {count}/{len(replacements)} replacements")
print(f"Remaining U+FFFD count: {s.count(chr(0xFFFD))}")

with open(f, 'w', encoding='utf-8', newline='') as fp:
    fp.write(s)
print("Saved.")
