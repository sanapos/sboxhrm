---
site: hrm
slug: ket-noi-may-cham-cong-zkteco-qua-internet
title: Kết nối máy chấm công ZKTeco lên phần mềm qua Internet (ADMS) – hướng dẫn từ A đến Z
metaTitle: Kết nối máy chấm công ZKTeco qua Internet (ADMS) | SBOX HRM
metaDescription: Hướng dẫn kết nối máy chấm công ZKTeco lên phần mềm qua Internet bằng ADMS: cấu hình địa chỉ máy chủ, kiểm tra kết nối, đồng bộ nhân viên và xử lý lỗi thường gặp.
keywords: máy chấm công ZKTeco, kết nối máy chấm công, ADMS, chấm công qua Internet, máy chấm công khuôn mặt
summary: Không cần máy tính bật suốt ngày để tải dữ liệu chấm công. Với ADMS, máy chấm công ZKTeco tự gửi lượt chấm lên phần mềm qua Internet ngay khi nhân viên chấm. Bài viết hướng dẫn cài đặt và xử lý lỗi thường gặp.
category: Máy chấm công
cover: /images/landing/screenshot-05.jpg
sortOrder: 10
---
Trước đây, muốn lấy dữ liệu từ máy chấm công, doanh nghiệp phải cắm USB hoặc để một máy tính trong văn phòng chạy phần mềm "kéo" dữ liệu qua mạng nội bộ. Nhiều chi nhánh thì nhiều máy tính, nhiều file — và mỗi lần mất điện, mất mạng lại thiếu dữ liệu.

**ADMS** (còn gọi là Push SDK) là cách kết nối mới: máy chấm công **tự gửi lượt chấm lên máy chủ phần mềm qua Internet**, giống như điện thoại gửi tin nhắn. Chỉ cần máy có mạng (dây LAN hoặc Wi-Fi) là dữ liệu từ mọi chi nhánh về chung một nơi.

## Máy nào hỗ trợ ADMS?

Phần lớn máy ZKTeco đời mới có menu **"Cài đặt máy chủ đám mây"** (Cloud Server Setting) hoặc **ADMS** đều kết nối được. Một số dòng phổ biến: máy chấm công khuôn mặt, máy vân tay màn hình màu (TFT), dòng LX, MB, SpeedFace, ProFace…

Cách kiểm tra nhanh: vào **Menu → Kết nối (Comm.) → Cài đặt máy chủ đám mây**. Nếu có mục này, máy hỗ trợ ADMS.

## Các bước kết nối

### Bước 1: Cho máy vào mạng Internet

- Dùng dây mạng LAN (ổn định nhất) hoặc Wi-Fi nếu máy có Wi-Fi.
- Vào **Menu → Kết nối → Ethernet**, bật DHCP để máy tự nhận địa chỉ IP.
- Kiểm tra máy truy cập được Internet (một số mạng công ty chặn kết nối ra ngoài).

### Bước 2: Khai báo địa chỉ máy chủ

Trong **Cài đặt máy chủ đám mây**:

| Mục | Giá trị |
|---|---|
| Địa chỉ máy chủ | Tên miền do nhà cung cấp phần mềm cung cấp |
| Cổng | 80 (hoặc 443 nếu dùng HTTPS) |
| Bật tên miền | Có |
| Proxy | Tắt |

Lưu lại và khởi động lại máy nếu được yêu cầu. Biểu tượng đám mây trên màn hình máy chuyển sang trạng thái đã kết nối là thành công.

### Bước 3: Gắn máy vào tài khoản doanh nghiệp

Trên phần mềm, nhập **số serial (SN)** in ở mặt sau máy hoặc trong **Menu → Thông tin hệ thống**. Máy được gắn vào cửa hàng / chi nhánh của bạn.

### Bước 4: Đồng bộ nhân viên

Có hai hướng:

- **Từ phần mềm xuống máy:** thêm nhân viên trên phần mềm, hệ thống tự đẩy mã chấm công và tên xuống máy. Nhân viên chỉ cần đăng ký vân tay hoặc khuôn mặt trực tiếp trên máy.
- **Từ máy lên phần mềm:** nhân viên đã có sẵn trên máy sẽ được gửi lên, bạn ghép với hồ sơ nhân viên trên phần mềm.

Từ lúc này, mỗi lượt chấm sẽ hiện trên phần mềm gần như ngay lập tức.

## Lỗi thường gặp và cách xử lý

### Máy báo "Offline" hoặc không thấy biểu tượng đám mây

- Kiểm tra dây mạng, thử cắm laptop vào cùng dây xem có Internet không.
- Kiểm tra lại địa chỉ máy chủ, không thừa dấu cách, không có "http://".
- Một số mạng (khách sạn, tòa nhà văn phòng) chặn cổng ra ngoài — nhờ bộ phận IT mở cổng 80/443.

### Có lượt chấm trên máy nhưng không thấy trên phần mềm

- Máy có thể đang lưu lượt chấm chưa gửi do mất mạng trước đó; khi có mạng lại máy sẽ tự gửi bù.
- Kiểm tra nhân viên trên máy đã được ghép với hồ sơ trên phần mềm chưa (đúng mã chấm công).
- Giờ trên máy sai múi giờ cũng khiến lượt chấm rơi vào ngày khác — bật đồng bộ giờ từ máy chủ.

### Không đăng ký được vân tay từ xa

Một số dòng máy giá rẻ **không hỗ trợ đăng ký vân tay, khuôn mặt từ phần mềm**. Khi đó hãy đăng ký trực tiếp trên máy: **Menu → Quản lý người dùng → chọn nhân viên → Vân tay / Khuôn mặt**.

## Nên chọn máy chấm công nào?

- **Văn phòng, cửa hàng nhỏ:** máy vân tay + thẻ có Wi-Fi là đủ.
- **Nhà máy, công trường, môi trường nhiều bụi:** máy khuôn mặt hoặc khuôn mặt + lòng bàn tay, không cần chạm.
- **Nhiều chi nhánh:** ưu tiên máy hỗ trợ ADMS để quản lý tập trung, không cần máy tính tại từng chi nhánh.

## Kết nối với SBOX HRM

[SBOX HRM](/) nhận dữ liệu trực tiếp từ máy chấm công ZKTeco qua ADMS, tự ghép với ca làm việc và [tính lương theo ngày công](/bai-viet/cach-tinh-luong-theo-ngay-cong) ngay trên phần mềm. Xem [hướng dẫn chi tiết](/guide.html) hoặc [đăng ký dùng thử miễn phí](/register) — đội kỹ thuật SBOX hỗ trợ cấu hình máy cho bạn.
