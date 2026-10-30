---
site: hrm
slug: xem-cham-cong-tren-macbook
title: Phần mềm chấm công cho MacBook: vì sao phần mềm đi kèm máy không chạy trên Mac và 3 cách xem công
metaTitle: Phần mềm chấm công cho MacBook: 3 cách xem công
metaDescription: Phần mềm chấm công cho MacBook: vì sao phần mềm đi kèm máy chấm công không chạy trên macOS, ưu nhược điểm máy ảo, Boot Camp, điều khiển từ xa và trình duyệt.
keywords: phần mềm chấm công cho macbook, phần mềm máy chấm công trên mac, chấm công trên macos, xem chấm công trên macbook, máy chấm công macbook, phần mềm chấm công không cần cài đặt
summary: Phần mềm đi kèm máy chấm công hầu hết chỉ chạy trên Windows, nên người dùng MacBook thường phải xoay xở. Bài viết giải thích nguyên nhân, so sánh các cách tạm như máy ảo, Boot Camp, điều khiển từ xa và cách xem công bằng trình duyệt.
category: Chấm công
cover: /images/blog/xem-cham-cong-tren-macbook.jpg
sortOrder: 60
---
Bạn vừa mua máy chấm công vân tay hoặc khuôn mặt, nhận kèm một đĩa hoặc đường link tải phần mềm, mở MacBook lên cài thì không được. Tìm **phần mềm chấm công cho MacBook** trên mạng cũng chỉ thấy các bản dành cho Windows. Đây là tình huống rất phổ biến ở các chủ doanh nghiệp, kế toán và quản lý dùng Mac.

Bài viết này giải thích vì sao **phần mềm máy chấm công trên Mac** gần như không tồn tại, đánh giá khách quan ba cách tạm mà nhiều người đang dùng, và giới thiệu cách xem công trực tiếp trên trình duyệt mà không cần cài gì.

## Vì sao phần mềm đi kèm máy chấm công không chạy trên MacBook?

- **Viết riêng cho Windows**: phần mềm đi kèm máy thường được phát triển từ nhiều năm trước, dùng thư viện và cơ sở dữ liệu chỉ có trên Windows; viết lại cho macOS tốn công nên ít nhà sản xuất làm.
- **Giao tiếp với máy chấm công qua thư viện riêng**: để tải dữ liệu qua mạng LAN hoặc USB, phần mềm dùng bộ thư viện kết nối (SDK) của hãng, phần lớn chỉ phát hành cho Windows.
- **Dữ liệu lưu cục bộ**: bảng công nằm trong ổ cứng của chính máy tính cài phần mềm. Không có máy chủ trung tâm nên cũng không có phiên bản web để mở từ máy khác.
- **macOS thay đổi kiến trúc**: từ khi Apple chuyển sang chip riêng (M1, M2 và các đời sau), ngay cả những công cụ cũ từng chạy được trên Mac đời Intel cũng có thể gặp vấn đề tương thích.

Kết quả là người dùng MacBook muốn **xem chấm công trên MacBook** phải tìm đường vòng.

## 3 cách tạm để chạy phần mềm chấm công Windows trên Mac

### Cách 1: Cài máy ảo Windows (Parallels, VMware Fusion, UTM...)

Máy ảo cho phép chạy Windows như một ứng dụng bên trong macOS. Bạn cài phần mềm chấm công vào Windows ảo đó và dùng như trên máy tính thường.

**Ưu điểm**: dùng được trên cả Mac chip Intel lẫn chip Apple, không cần khởi động lại máy, chuyển qua lại giữa macOS và Windows nhanh.

**Nhược điểm cần biết**:

- Cần bản quyền phần mềm máy ảo (một số loại tính phí) và bản quyền Windows.
- Trên Mac chip Apple, Windows chạy là bản dành cho chip ARM; phần mềm chấm công cũ phải chạy qua lớp giả lập, có thể chậm hoặc lỗi ở phần kết nối máy chấm công, nhất là khi cắm USB.
- Máy ảo chiếm nhiều RAM và ổ cứng.
- Muốn tải dữ liệu qua LAN, MacBook vẫn phải ở cùng mạng với máy chấm công, tức là phải ngồi ở văn phòng.

### Cách 2: Boot Camp (chỉ áp dụng cho Mac chip Intel)

Boot Camp là công cụ của Apple cho phép cài Windows song song trên ổ cứng, khi bật máy chọn vào macOS hoặc Windows.

**Ưu điểm**: Windows chạy trực tiếp trên phần cứng nên ổn định, tương thích tốt với phần mềm chấm công cũ.

**Nhược điểm**:

- **Không có trên Mac dùng chip Apple** (M1 trở đi). Nếu MacBook của bạn mua trong vài năm gần đây, cách này gần như không áp dụng được.
- Mỗi lần xem công phải khởi động lại máy sang Windows, rồi khởi động lại để quay về macOS.
- Phải chia ổ cứng, quản lý hai hệ điều hành, tự cập nhật và diệt virus cho phần Windows.

### Cách 3: Điều khiển từ xa một máy tính Windows

Nhiều doanh nghiệp để một máy Windows ở văn phòng chạy phần mềm chấm công, rồi dùng phần mềm điều khiển từ xa (remote desktop) để truy cập từ MacBook.

**Ưu điểm**: không phải cài gì nặng trên Mac, có thể xem công khi ở ngoài văn phòng.

**Nhược điểm**:

- Máy Windows ở văn phòng phải **bật liên tục** và luôn có mạng; mất điện, Windows tự cập nhật hay treo máy là mất kết nối.
- Thao tác qua màn hình từ xa chậm, giật khi mạng yếu, khó dùng trên màn hình nhỏ.
- Dữ liệu vẫn nằm trong một ổ cứng duy nhất; hỏng máy là phải khôi phục từ bản sao lưu (nếu có).

## Bảng so sánh các cách chấm công trên macOS

| Tiêu chí | Máy ảo Windows | Boot Camp | Điều khiển từ xa | Phần mềm chấm công trên trình duyệt |
|---|---|---|---|---|
| Mac chip Apple (M1 trở đi) | Được, có thể lỗi tương thích | Không | Được | Được |
| Mac chip Intel | Được | Được | Được | Được |
| Cần bản quyền Windows | Có | Có | Có (máy văn phòng) | Không |
| Cài đặt trên MacBook | Nặng | Rất nặng | Nhẹ | Không cần |
| Xem công khi ở ngoài văn phòng | Hạn chế | Hạn chế | Được nếu máy văn phòng bật | Được |
| Xem trên điện thoại | Không | Không | Khó | Có app riêng |
| Phụ thuộc một máy tính | Có | Có | Có | Không |

Ba cách đầu đều **giữ nguyên phần mềm Windows** và tìm cách với tới nó, nên dữ liệu vẫn kẹt trong một máy tính.

## Cách thứ tư: xem chấm công trên MacBook bằng trình duyệt

Thay vì chạy phần mềm Windows trên Mac, hướng lâu dài là dùng **phần mềm chấm công chạy trên web**. Với SBOX HRM, bạn chỉ cần mở Safari, Chrome, Edge hoặc Cốc Cốc trên MacBook, đăng nhập và xem bảng công. Không cài đặt, không phụ thuộc chip Intel hay chip Apple, không cần bản quyền Windows. Chi tiết tính năng xem tại trang [phần mềm chấm công cho MacBook](/tinh-nang/phan-mem-cham-cong-macbook).

### Dữ liệu từ máy chấm công lên trình duyệt bằng cách nào?

Máy chấm công ZKTeco có chức năng **ADMS / Push / Cloud Server** sẽ tự gửi từng lượt chấm qua Internet về máy chủ SBOX, không cần máy tính trung gian để kéo dữ liệu, **không cần IP tĩnh hay mở port** modem. Nếu mạng ở văn phòng bị gián đoạn, máy vẫn lưu bản ghi và gửi bù khi có mạng lại. Cách khai báo trên máy được hướng dẫn trong bài [kết nối máy chấm công ZKTeco qua Internet](/bai-viet/ket-noi-may-cham-cong-zkteco-qua-internet).

### Những việc làm được ngay trên MacBook

- Xem bảng công theo ngày, tuần, tháng; ai đi trễ, về sớm, thiếu giờ vào hoặc giờ ra.
- Xem trạng thái máy chấm công đang kết nối hay mất kết nối.
- Quản lý nhân viên trên máy chấm công từ phần mềm, đồng bộ hai chiều.
- Chuyển bảng công sang [bảng lương tự động](/tinh-nang/phan-mem-tinh-luong) và xuất Excel gửi kế toán.

Ngoài MacBook, cùng một tài khoản dùng được trên máy Windows, máy tính bảng và app Android, iOS. Nếu bạn hay xem công khi đi công tác, tham khảo thêm [cách xem dữ liệu máy chấm công trên điện thoại](/bai-viet/cach-xem-du-lieu-may-cham-cong-tren-dien-thoai).

## Chuyển từ phần mềm Windows sang trình duyệt: 4 bước

1. **Kiểm tra máy chấm công**: vào menu Kết nối (Comm.) của máy, tìm mục Cloud Server hoặc ADMS. Nếu không chắc, gửi model máy qua Zalo 0973 024 042 để kỹ thuật kiểm tra.
2. **Tạo tài khoản** và khai báo chi nhánh, ca làm việc, danh sách nhân viên.
3. **Khai báo địa chỉ máy chủ** trên máy chấm công và ghép mã chấm công với hồ sơ nhân viên.
4. **Chạy song song một kỳ công** với phần mềm cũ để đối chiếu, sau đó có thể ngừng dùng máy Windows.

Bài [chuyển phần mềm chấm công cài máy sang online](/bai-viet/chuyen-phan-mem-cham-cong-cai-may-sang-online) phân tích kỹ hơn những thay đổi khi bỏ phần mềm cài máy tính.

Máy đời cũ không có ADMS có thể chuyển sang chấm công điện thoại (khuôn mặt kèm GPS hoặc WiFi) hoặc thay máy có ADMS.

Muốn thử trên chính MacBook của bạn? [Đăng ký dùng thử miễn phí](/register), không cần thẻ thanh toán.

## Câu hỏi thường gặp

### Có phần mềm chấm công nào cài trực tiếp trên macOS không?
Rất ít. Phần lớn phần mềm đi kèm máy chấm công chỉ có bản Windows. Cách thuận tiện nhất cho người dùng Mac là dùng phần mềm chấm công chạy trên trình duyệt, không cần cài đặt.

### MacBook chip M1, M2 có dùng Boot Camp để chạy phần mềm chấm công được không?
Không. Boot Camp chỉ có trên Mac dùng chip Intel. Mac chip Apple chỉ chạy Windows qua máy ảo, và phần mềm chấm công cũ có thể gặp lỗi tương thích, nhất là khi kết nối máy chấm công qua USB.

### Xem chấm công trên MacBook bằng trình duyệt có cần máy tính Windows ở văn phòng không?
Không, nếu máy chấm công có ADMS. Máy tự gửi dữ liệu qua Internet lên máy chủ, MacBook chỉ cần mở trình duyệt và đăng nhập.

### Dùng Safari có được không hay bắt buộc Chrome?
SBOX HRM dùng được trên Safari, Chrome, Edge và Cốc Cốc. Bạn dùng trình duyệt quen thuộc trên Mac là được.

### Ngoài MacBook, quản lý có xem công trên iPhone được không?
Được. Quản lý và nhân viên dùng app SBOX HRM trên iOS và Android để xem công, duyệt đơn và xem phiếu lương.
