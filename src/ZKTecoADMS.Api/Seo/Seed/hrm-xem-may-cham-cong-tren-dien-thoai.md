---
site: hrm
slug: cach-xem-du-lieu-may-cham-cong-tren-dien-thoai
title: Cách xem dữ liệu máy chấm công trên điện thoại từ xa (không cần IP tĩnh)
metaTitle: Xem máy chấm công trên điện thoại từ xa, không cần IP tĩnh
metaDescription: Cách xem máy chấm công trên điện thoại từ xa: so sánh IP tĩnh, DDNS, mở port, điều khiển máy tính từ xa với kết nối ADMS không cần IP tĩnh, kèm các bước cài.
keywords: xem máy chấm công trên điện thoại, quản lý máy chấm công qua điện thoại, xem dữ liệu máy chấm công từ xa, app xem chấm công, máy chấm công không cần ip tĩnh, adms
summary: Muốn mở điện thoại là biết ai đã vào ca mà không phải gọi về văn phòng? Bài viết điểm lại các cách cũ như IP tĩnh, DDNS, mở port, điều khiển máy tính từ xa và vì sao chúng hay trục trặc, rồi hướng dẫn cách dùng ADMS để xem dữ liệu máy chấm công từ xa.
category: Máy chấm công
cover: /images/blog/cach-xem-du-lieu-may-cham-cong-tren-dien-thoai.jpg
sortOrder: 60
---
Bạn đang đi công tác hoặc ngồi nhà buổi sáng và muốn biết **ca sáng nay đã đủ người chưa**. Câu hỏi quen thuộc của rất nhiều chủ cửa hàng là: làm sao **xem máy chấm công trên điện thoại** mà không phải gọi kế toán tải dữ liệu? Bài viết này điểm lại những cách mà các kỹ thuật viên hay làm trước đây, lý do chúng hay trục trặc, và cách xem dữ liệu máy chấm công từ xa ổn định hơn mà **không cần IP tĩnh**.

## Vì sao không xem được máy chấm công từ xa ngay từ đầu?

Máy chấm công truyền thống **chờ máy tính trong mạng nội bộ hỏi dữ liệu** qua địa chỉ IP nội bộ (dạng 192.168.x.x). Địa chỉ này chỉ có nghĩa bên trong mạng văn phòng; từ điện thoại dùng 4G bên ngoài, bạn không "nhìn thấy" nó.

Vì vậy mọi cách cũ đều xoay quanh một ý: **tìm đường để từ bên ngoài đi vào mạng văn phòng**. Và chính con đường đi vào đó là nguồn gốc của phần lớn rắc rối.

## Các cách cũ để xem dữ liệu máy chấm công từ xa

### Cách 1: Thuê IP tĩnh hoặc dùng DDNS, rồi mở port trên modem

Kỹ thuật viên đăng ký IP tĩnh với nhà mạng (hoặc dùng dịch vụ DDNS để có một tên miền trỏ về IP động của modem), sau đó cấu hình modem chuyển tiếp một cổng (port forwarding) vào máy chấm công. Phần mềm ở nơi khác kết nối tới địa chỉ đó để kéo dữ liệu.

Nhược điểm:

- **IP tĩnh thường phát sinh chi phí** với nhà mạng; DDNS miễn phí thì hay mất cập nhật khi modem khởi động lại.
- **Thay modem, nhà mạng reset cấu hình** là mất port forwarding, phải gọi kỹ thuật cài lại.
- Mở cổng từ Internet vào thẳng thiết bị nội bộ là **tăng rủi ro bảo mật**.
- Nhiều mạng tòa nhà, mạng dùng chung địa chỉ **không mở port được**; và cuối cùng vẫn cần phần mềm cài máy tính để kéo dữ liệu.

### Cách 2: Điều khiển máy tính văn phòng từ xa

Cách "chữa cháy" phổ biến nhất: để máy tính văn phòng chạy phần mềm chấm công, cài phần mềm điều khiển từ xa như TeamViewer, UltraViewer, rồi từ điện thoại truy cập vào màn hình máy tính đó.

Nhược điểm:

- Máy tính văn phòng **phải bật 24/7**; mất điện, Windows tự cập nhật hoặc ai đó tắt máy là hết xem.
- Thao tác phần mềm máy tính trên màn hình điện thoại nhỏ **rất khó**, dễ bấm nhầm lệnh xóa dữ liệu.
- Cho quản lý chi nhánh truy cập là **giao cả chiếc máy tính**, không phân quyền được.

## Cách mới: máy chấm công tự gửi dữ liệu qua ADMS

Các máy ZKTeco đời mới có chức năng **ADMS** (còn gọi Push, Cloud Server). Thay vì chờ được hỏi, máy **chủ động gửi lượt chấm ra máy chủ phần mềm trên Internet** vài giây sau khi nhân viên chấm. Chiều kết nối đảo ngược: từ trong ra ngoài, giống cách điện thoại gửi tin nhắn.

Nhờ vậy:

- **Không cần IP tĩnh, không cần DDNS, không mở port** trên modem.
- **Không cần máy tính** bật ở văn phòng; dữ liệu nằm trên máy chủ.
- Điện thoại, máy tính bảng, MacBook chỉ cần đăng nhập là xem, không phải "đi vào" mạng văn phòng.
- Mất mạng thì máy lưu lại bản ghi và **tự gửi bù** khi có mạng.

| Tiêu chí | IP tĩnh / DDNS + mở port | Điều khiển máy tính từ xa | ADMS lên cloud |
|---|---|---|---|
| Cần IP tĩnh hoặc tên miền động | Có | Không | Không |
| Cấu hình modem | Phải mở port | Không | Không |
| Máy tính văn phòng bật 24/7 | Thường có | Bắt buộc | Không |
| Xem trực tiếp trên điện thoại | Không, vẫn qua phần mềm máy tính | Gián tiếp, khó thao tác | Có, qua app hoặc trình duyệt |
| Đổi modem, đổi nhà mạng | Phải cài lại | Thường không ảnh hưởng | Không ảnh hưởng nếu máy vẫn có Internet |
| Phân quyền theo người xem | Hạn chế | Không | Theo tài khoản |
| Dữ liệu cập nhật | Khi có người kéo về | Khi có người tải | Vài giây sau mỗi lượt chấm |

## Các bước xem máy chấm công trên điện thoại bằng ADMS

### Bước 1: Kiểm tra máy có ADMS

Trên máy chấm công, vào **Menu → Kết nối (Comm.)** và tìm mục **Cài đặt máy chủ đám mây** (Cloud Server Setting) hoặc **ADMS**. Có mục này là máy gửi dữ liệu qua Internet được. Nếu không chắc, chụp model máy gửi qua Zalo 0973 024 042 để kỹ thuật SBOX kiểm tra miễn phí.

### Bước 2: Cho máy vào mạng

Cắm dây LAN hoặc kết nối WiFi nếu máy có WiFi. Vào **Menu → Kết nối → Ethernet**, bật **DHCP**. Không cần cấu hình gì thêm trên modem.

### Bước 3: Khai báo máy chủ và gắn máy vào tài khoản

Trong mục Cài đặt máy chủ đám mây, nhập địa chỉ máy chủ do nhà cung cấp phần mềm đưa, bật tên miền, tắt proxy. Trên phần mềm, nhập số serial (SN) của máy để gắn máy vào đúng chi nhánh. Hướng dẫn chi tiết từng mục có trong bài [kết nối máy chấm công ZKTeco qua Internet](/bai-viet/ket-noi-may-cham-cong-zkteco-qua-internet).

### Bước 4: Ghép mã nhân viên

Đồng bộ danh sách người dùng giữa máy và phần mềm, đảm bảo mỗi mã chấm công trên máy khớp một hồ sơ nhân viên. Bước này quyết định bảng công có đúng người hay không.

### Bước 5: Cài app và phân quyền người xem

Cài app trên điện thoại Android hoặc iOS, hoặc mở trình duyệt và đăng nhập. Tạo tài khoản riêng cho từng quản lý chi nhánh để mỗi người chỉ thấy phần việc của mình.

## Trên điện thoại xem được những gì?

Với một app xem chấm công dạng cloud như SBOX HRM, người quản lý có thể:

- Xem **lượt chấm mới nhất** của từng nhân viên, ai đã vào ca, ai chưa đến.
- Xem **trạng thái từng máy chấm công**: online hay offline, thời điểm gửi dữ liệu gần nhất.
- Mở **bảng công** với đi trễ, về sớm, quên chấm theo ca.
- Duyệt **đơn nghỉ phép, tăng ca** nhân viên gửi trên app.
- Quản lý người dùng trên máy: thêm nhân viên mới trên phần mềm, mã và tên được đẩy xuống máy.

Cửa hàng chưa có máy chấm công, hoặc có nhân viên làm ngoài, có thể bổ sung [chấm công bằng khuôn mặt trên điện thoại](/tinh-nang/cham-cong-khuon-mat-dien-thoai) kèm kiểm tra GPS, WiFi và khóa đúng thiết bị đã đăng ký.

## Lỗi thường gặp khi xem dữ liệu máy chấm công từ xa

### App báo máy offline

Kiểm tra dây mạng, đèn modem, mật khẩu WiFi; mạng tòa nhà có tường lửa thì nhờ IT mở kết nối ra máy chủ. Các nguyên nhân khác được tổng hợp trong bài [máy chấm công ZKTeco mất kết nối](/bai-viet/may-cham-cong-zkteco-mat-ket-noi).

### Có lượt chấm trên máy nhưng app chưa hiện

Máy đang chờ gửi bù sau khi mất mạng, hoặc mã người dùng chưa được ghép hồ sơ.

### Giờ chấm trên app lệch so với thực tế

Máy sai giờ hoặc sai múi giờ. Đặt GMT+7 và đồng bộ giờ cho máy.

## Xem thêm

Nếu bạn đang tìm máy mới phù hợp cách làm này, bài [máy chấm công không cần máy tính](/bai-viet/may-cham-cong-khong-can-may-tinh) gợi ý dòng máy và cách cài đặt. Phần giới thiệu tính năng có tại trang [quản lý máy chấm công trên điện thoại](/tinh-nang/quan-ly-may-cham-cong-tren-dien-thoai).

[Đăng ký dùng thử SBOX HRM miễn phí](/register), không cần thẻ thanh toán; kỹ thuật hỗ trợ khai báo ADMS cho máy của bạn qua Zalo 0973 024 042.

## Câu hỏi thường gặp

### Có app nào xem máy chấm công trên điện thoại mà không cần IP tĩnh không?
Có. Nếu máy ZKTeco có ADMS, máy tự gửi dữ liệu lên phần mềm cloud; bạn xem bằng app hoặc trình duyệt trên điện thoại mà không cần IP tĩnh hay mở port.

### Máy chấm công không có ADMS thì xem từ xa được không?
Chỉ xem gián tiếp qua các cách cũ như mở port hoặc điều khiển máy tính văn phòng. Cách ổn định hơn là thay máy có ADMS hoặc dùng chấm công bằng điện thoại.

### Xem trên điện thoại có cần máy tính văn phòng bật không?
Không, khi dùng ADMS. Dữ liệu đi thẳng từ máy chấm công lên máy chủ, điện thoại đọc từ máy chủ.

### Nhiều chi nhánh có xem chung trên một app được không?
Được. Mỗi máy gắn vào một chi nhánh theo số serial, chủ doanh nghiệp xem tất cả trên một tài khoản, quản lý chi nhánh chỉ xem phần được phân quyền.
