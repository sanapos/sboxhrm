---
site: hrm
slug: may-cham-cong-khong-can-may-tinh
title: Máy chấm công không cần máy tính: dòng nào dùng được, cài đặt thế nào
metaTitle: Máy chấm công không cần máy tính: chọn dòng nào, cài sao
metaDescription: Máy chấm công không cần máy tính hoạt động thế nào, dòng ZKTeco nào có ADMS kết nối Internet, cách kiểm tra, cài đặt từng bước và lỗi hay gặp khi lắp mới.
keywords: máy chấm công không cần máy tính, máy chấm công kết nối internet, máy chấm công cloud, máy chấm công adms, máy chấm công zkteco adms, máy chấm công wifi
summary: Không phải máy chấm công nào cũng bỏ được máy tính văn phòng. Bài viết giải thích điều kiện để một máy chấm công gửi dữ liệu thẳng lên Internet, cách nhận biết dòng máy có ADMS, ví dụ thông số MB10-VL và SenseFace 2A, cùng quy trình lắp đặt và các lỗi hay gặp.
category: Máy chấm công
cover: /images/blog/may-cham-cong-khong-can-may-tinh.jpg
sortOrder: 60
---
"Có loại **máy chấm công không cần máy tính** không?" là câu hỏi thường gặp ở cửa hàng nhỏ, quán ăn, chi nhánh mới mở — nơi không có máy tính bật suốt ngày. Câu trả lời là có, nhưng cần hiểu đúng: máy vẫn cần một phần mềm để tính công, chỉ là phần mềm đó **không nằm trên máy tính của bạn** mà nằm trên Internet. Bài viết giúp bạn nhận biết dòng máy dùng được, chuẩn bị gì trước khi lắp và cài đặt ra sao.

## "Không cần máy tính" nghĩa là gì?

Có hai cách hiểu, và người bán đôi khi dùng lẫn lộn:

1. **Máy tự lưu, xuất file qua USB**: máy ghi lượt chấm trong bộ nhớ, cuối tháng cắm USB chép file rồi mở bằng Excel hay phần mềm trên một máy tính nào đó. Không cần máy tính *bật thường xuyên*, nhưng vẫn cần máy tính *để xử lý*.
2. **Máy chấm công kết nối Internet, gửi lên cloud**: máy tự gửi từng lượt chấm lên máy chủ phần mềm qua mạng, quản lý xem bảng công trên điện thoại hoặc trình duyệt. Đây mới là "không cần máy tính" theo nghĩa đầy đủ.

Bài viết này nói về cách thứ hai — thường được gọi là **máy chấm công cloud** hay **máy chấm công ADMS**.

## Điều kiện để máy chấm công kết nối Internet không cần máy tính

Một máy chấm công làm được việc này khi hội đủ ba điều kiện:

- **Có cổng mạng**: cổng LAN (TCP/IP) hoặc WiFi để ra Internet.
- **Có chức năng ADMS / Push / Cloud Server** trong firmware: cho phép khai báo địa chỉ máy chủ để máy chủ động gửi dữ liệu lên.
- **Có phần mềm cloud nhận dữ liệu** từ máy theo giao thức đó.

Có cổng mạng **chưa đủ**: nhiều máy đời cũ có cổng LAN nhưng chỉ chờ máy tính cùng mạng nội bộ hỏi dữ liệu. ADMS mới là chìa khóa — máy gửi ra ngoài nên không cần IP tĩnh, không mở port.

## Cách nhận biết máy chấm công ADMS

### Kiểm tra trên máy đang có

Vào **Menu → Kết nối (Comm.)**, tìm mục **Cài đặt máy chủ đám mây** (Cloud Server Setting) hoặc **ADMS**. Thấy mục này là máy hỗ trợ gửi dữ liệu qua Internet.

### Kiểm tra trước khi mua

- Xem thông số do hãng công bố có ghi **ADMS** trong phần chức năng hay không.
- Phần lớn máy ZKTeco đời mới — máy khuôn mặt, máy vân tay màn hình màu, các dòng LX, MB, SpeedFace, ProFace — có mục Cloud Server.
- Hỏi người bán model chính xác và gửi model qua Zalo 0973 024 042 để kỹ thuật SBOX kiểm tra miễn phí trước khi xuống tiền.

### Chú ý firmware rút gọn

Một số dòng máy giá rẻ vẫn gửi được lượt chấm lên phần mềm nhưng **không nhận một số lệnh từ xa**, ví dụ đăng ký vân tay từ phần mềm. Với dòng này, bạn đăng ký vân tay, khuôn mặt trực tiếp trên máy; chấm công hằng ngày vẫn tự lên phần mềm bình thường.

## Ví dụ hai dòng máy và thông số liên quan

Dưới đây là thông số do hãng công bố của hai máy trong danh mục lắp đặt của SBOX, chỉ ghi các mục liên quan đến việc dùng không cần máy tính.

| Mục | ZKTeco MB10-VL | ZKTeco SenseFace 2A |
|---|---|---|
| Chấm công bằng | Khuôn mặt, vân tay, thẻ | Khuôn mặt, vân tay, thẻ |
| Dung lượng khuôn mặt | 100 (tùy chọn nâng lên 800) | 1.500 (bản Entry) hoặc 3.000 (bản Standard) |
| Dung lượng vân tay | 500 (tùy chọn nâng lên 800) | 1.500 (bản Entry) hoặc 3.000 (bản Standard) |
| Bản ghi chấm công | 50.000 (tùy chọn nâng lên 150.000) | 150.000 |
| Kết nối | TCP/IP, USB Host, WiFi (tùy chọn) | Kỹ thuật SBOX xác nhận theo phiên bản khi báo giá |
| ADMS | Có, là chức năng chuẩn | Kiểm tra theo phiên bản trước khi mua |
| Điểm đáng chú ý | Khoảng cách nhận diện 30 – 50 cm, dưới 1 giây | Màn hình 2,4 inch TFT màu, khuôn mặt dưới 0,35 giây |

**MB10-VL** ghi rõ ADMS trong chức năng chuẩn: cắm mạng, khai báo máy chủ là gửi dữ liệu. Dung lượng mặc định vừa cửa hàng, văn phòng nhỏ; chỗ không có dây mạng thì hỏi bản có WiFi.

**SenseFace 2A** có dung lượng lớn hơn, hợp nơi đông nhân viên. Thông số chính hãng chúng tôi đối chiếu không nêu chi tiết phần kết nối, nên hãy để kỹ thuật xác nhận phiên bản có ADMS trước khi đặt mua.

Thông số có thể khác nhau theo phiên bản và tùy chọn nâng cấp; SBOX báo đúng cấu hình khi báo giá. Danh sách máy và dịch vụ lắp tận nơi có ở trang [lắp đặt máy chấm công](/lap-dat-may-cham-cong).

## Cài đặt máy chấm công cloud từng bước

### Bước 1: Chọn vị trí có mạng

Đặt máy gần ổ điện và dây mạng LAN (ổn định hơn WiFi); thử cắm laptop vào sợi dây đó để chắc có Internet.

### Bước 2: Cho máy nhận mạng

Vào **Menu → Kết nối → Ethernet**, bật **DHCP** để máy tự nhận địa chỉ IP. Máy có WiFi thì chọn mạng WiFi và nhập mật khẩu.

### Bước 3: Khai báo máy chủ đám mây

Trong **Cài đặt máy chủ đám mây**, nhập địa chỉ máy chủ do nhà cung cấp phần mềm đưa, cổng theo hướng dẫn, bật tên miền, tắt proxy. Lưu lại; biểu tượng đám mây trên màn hình chuyển trạng thái đã kết nối là thành công. Chi tiết từng mục xem bài [kết nối máy chấm công ZKTeco qua Internet](/bai-viet/ket-noi-may-cham-cong-zkteco-qua-internet).

### Bước 4: Gắn máy vào tài khoản

Trên phần mềm, nhập số serial (SN) in ở mặt sau máy hoặc trong **Menu → Thông tin hệ thống**, chọn chi nhánh đặt máy.

### Bước 5: Đưa nhân viên lên máy

Thêm nhân viên trên phần mềm để mã và tên tự đẩy xuống máy, rồi cho từng người đăng ký khuôn mặt hoặc vân tay trên máy. Nhân viên đã có sẵn trên máy thì được gửi ngược lên để ghép hồ sơ.

### Bước 6: Đặt ca và kiểm tra

Khai báo ca làm việc, cho vài người chấm thử và xem lượt chấm hiện trên phần mềm.

## Lỗi hay gặp khi lắp máy chấm công không cần máy tính

### Mua máy có cổng mạng nhưng không có ADMS

Lỗi tốn kém nhất: máy chỉ dùng được với phần mềm cài máy tính. Luôn hỏi rõ "có Cloud Server / ADMS không".

### Đặt máy ở chỗ sóng WiFi yếu

Máy chập chờn mạng; dữ liệu không mất vì được gửi bù, nhưng bảng công sẽ trễ. Kéo dây LAN là chắc nhất.

### Sai giờ, sai múi giờ

Lượt chấm rơi sang ngày khác; đặt GMT+7 ngay khi lắp.

### Mạng tòa nhà chặn kết nối ra ngoài

Nhờ IT cho phép kết nối tới địa chỉ máy chủ.

## Khi nào nên chọn máy chấm công cloud?

- **Cửa hàng, quán nhỏ** không có máy tính văn phòng.
- **Chủ doanh nghiệp hay đi lại**, muốn xem công trên điện thoại.
- **Nhiều chi nhánh**: mỗi nơi một máy, tất cả về một tài khoản — xem thêm bài [quản lý máy chấm công nhiều chi nhánh](/bai-viet/quan-ly-may-cham-cong-nhieu-chi-nhanh).
- **Muốn nối thẳng sang tính lương**, bỏ bước xuất Excel.

Còn băn khoăn giữa phần mềm cài máy và cloud, bài [phần mềm quản lý máy chấm công là gì](/bai-viet/phan-mem-quan-ly-may-cham-cong-la-gi) so sánh chi tiết hai kiểu.

## Dùng với SBOX HRM

[SBOX HRM](/tinh-nang/phan-mem-cham-cong-zkteco) nhận dữ liệu máy ZKTeco qua ADMS, hiện trạng thái online / offline của từng máy, đồng bộ người dùng hai chiều và tính công, tính lương ngay trên phần mềm. Bạn xem trên trình duyệt (Chrome, Safari, Edge, Cốc Cốc) hoặc app Android, iOS. Mua máy tại SBOX được miễn phí lắp đặt và tặng phần mềm. [Đăng ký dùng thử miễn phí](/register), không cần thẻ thanh toán.

## Câu hỏi thường gặp

### Máy chấm công không cần máy tính có phải mua phần mềm riêng không?
Máy cần một phần mềm cloud để nhận dữ liệu và tính công. Khi mua máy tại SBOX, bạn được tặng phần mềm chấm công SBOX HRM.

### Máy chấm công kết nối Internet có cần IP tĩnh không?
Không, nếu máy dùng ADMS. Máy chủ động gửi dữ liệu ra máy chủ nên không cần IP tĩnh hay mở port modem.

### Mất mạng thì máy chấm công cloud có mất dữ liệu không?
Không. Máy lưu bản ghi trong bộ nhớ và tự gửi bù khi có mạng lại, miễn là bộ nhớ chưa đầy.

### Máy cũ không có ADMS thì làm sao bỏ được máy tính?
Có thể thay máy đời mới có ADMS, hoặc chuyển sang chấm công bằng khuôn mặt trên điện thoại kèm GPS, WiFi cho cửa hàng nhỏ.
