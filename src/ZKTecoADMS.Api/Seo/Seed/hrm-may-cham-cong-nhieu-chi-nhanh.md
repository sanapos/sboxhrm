---
site: hrm
slug: quan-ly-may-cham-cong-nhieu-chi-nhanh
title: Quản lý máy chấm công nhiều chi nhánh tập trung trên một tài khoản
metaTitle: Quản lý máy chấm công nhiều chi nhánh tập trung
metaDescription: Hướng dẫn quản lý máy chấm công nhiều chi nhánh trên một tài khoản: triển khai từng bước, đồng bộ nhân viên giữa các máy, luân chuyển và chấm công điện thoại.
keywords: quản lý máy chấm công nhiều chi nhánh, chấm công nhiều chi nhánh, đồng bộ máy chấm công, quản lý chuỗi cửa hàng chấm công, chấm công chuỗi cửa hàng, máy chấm công nhiều địa điểm
summary: Chuỗi cửa hàng, nhà hàng hay công ty nhiều văn phòng thường gặp cảnh mỗi nơi một máy chấm công, cuối tháng gom file bằng tay. Bài viết hướng dẫn gom tất cả máy về một tài khoản, đồng bộ nhân viên giữa các máy, xử lý nhân viên luân chuyển và điểm không có máy.
category: Máy chấm công
cover: /images/blog/quan-ly-may-cham-cong-nhieu-chi-nhanh.jpg
sortOrder: 60
---
Khi doanh nghiệp chỉ có một địa điểm, một máy chấm công và một file Excel là đủ. Nhưng từ chi nhánh thứ hai trở đi, mọi thứ nhân lên: mỗi nơi một máy, mỗi máy một danh sách nhân viên, mỗi cuối tháng một lần gom dữ liệu. **Quản lý máy chấm công nhiều chi nhánh** trở thành việc tốn thời gian nhất của bộ phận nhân sự, kế toán.

Bài viết này hướng dẫn cách đưa tất cả máy chấm công của các chi nhánh về **một tài khoản duy nhất**, cách đồng bộ nhân viên giữa các máy, xử lý nhân viên luân chuyển và kết hợp chấm công điện thoại cho những điểm không đặt máy.

## Những vấn đề thường gặp khi chấm công nhiều chi nhánh

Các tình huống quen thuộc ở chuỗi cửa hàng, nhà hàng, văn phòng đại diện:

- **Dữ liệu rời rạc**: mỗi chi nhánh tải dữ liệu bằng USB hoặc phần mềm cài máy riêng, gửi file về văn phòng, kế toán ghép lại. Sai một cột là lệch cả bảng công.
- **Mã nhân viên không thống nhất**: cùng một người nhưng máy chi nhánh A là mã 15, máy chi nhánh B là mã 102.
- **Nhân viên nghỉ việc vẫn còn trên máy**: không ai nhớ xóa, danh sách trên máy ngày càng rối.
- **Không biết máy nào đang hỏng**: máy chi nhánh xa mất kết nối cả tuần, đến cuối tháng mới phát hiện thiếu dữ liệu.
- **Nhân viên làm nhiều nơi**: người được điều sang chi nhánh khác phải đăng ký lại vân tay, khuôn mặt, hoặc chấm ở một nơi nhưng công ghi ở nơi khác.

Gốc vấn đề là **mỗi máy hoạt động như một hòn đảo**. Muốn **chấm công nhiều chi nhánh** hiệu quả, các máy phải cùng về một hệ thống trung tâm.

## Mô hình quản lý tập trung hoạt động thế nào?

Với máy chấm công ZKTeco có chức năng **ADMS / Push / Cloud Server**, mỗi máy tự kết nối qua Internet về máy chủ phần mềm. Không cần máy tính ở từng chi nhánh, **không cần IP tĩnh hay mở port** modem; chỉ cần đường mạng bình thường của cửa hàng.

| Thành phần | Cách tổ chức |
|---|---|
| Tài khoản doanh nghiệp | Một tài khoản chung cho cả chuỗi |
| Chi nhánh | Mỗi chi nhánh có ca, vị trí chấm công và quản lý riêng |
| Máy chấm công | Mỗi máy gán cho một chi nhánh |
| Nhân viên | Một hồ sơ duy nhất, gắn với chi nhánh đang làm |
| Bảng công, bảng lương | Xem theo từng chi nhánh hoặc toàn chuỗi |

Trên phần mềm, bạn thấy **trạng thái từng máy** đang kết nối hay mất kết nối, lần gửi dữ liệu gần nhất, số người dùng trên máy. Máy nào im lặng bất thường được phát hiện ngay chứ không phải chờ cuối tháng. Nếu mạng một chi nhánh gián đoạn, máy vẫn lưu bản ghi và gửi bù khi có mạng lại. Tìm hiểu thêm các chức năng ở trang [phần mềm quản lý máy chấm công](/tinh-nang/phan-mem-quan-ly-may-cham-cong).

## Quy trình triển khai từng bước

### Bước 1: Khảo sát máy chấm công ở các chi nhánh
Lập danh sách chi nhánh, model máy, số nhân viên. Kiểm tra trong menu Kết nối (Comm.) của mỗi máy có mục Cloud Server hoặc ADMS không. Máy không hỗ trợ thì chuẩn bị phương án thay máy hoặc chấm công điện thoại cho chi nhánh đó.

### Bước 2: Chuẩn hóa mã nhân viên
Đây là bước quan trọng nhất. Quy ước **mỗi nhân viên một mã chấm công duy nhất trên toàn chuỗi**, không trùng giữa các chi nhánh. Nếu các máy đang dùng mã lộn xộn, lập bảng đối chiếu mã cũ và mã mới trước khi kết nối.

### Bước 3: Tạo cấu trúc trên phần mềm
Tạo chi nhánh, phòng ban, phân quyền quản lý chi nhánh. Thiết lập [ca làm việc](/tinh-nang/quan-ly-ca-lam-viec) riêng cho từng nơi nếu giờ mở cửa khác nhau, ví dụ cửa hàng trung tâm thương mại mở muộn hơn cửa hàng mặt phố.

### Bước 4: Kết nối máy đầu tiên làm thí điểm
Khai báo địa chỉ máy chủ trên máy, gán máy vào chi nhánh tương ứng, tải danh sách người dùng trên máy về và ghép với hồ sơ nhân viên. Cách khai báo chi tiết xem bài [kết nối máy chấm công ZKTeco qua Internet](/bai-viet/ket-noi-may-cham-cong-zkteco-qua-internet).

### Bước 5: Nhân rộng ra các chi nhánh còn lại
Khi máy thí điểm chạy ổn vài ngày, lần lượt kết nối các máy còn lại.

### Bước 6: Chạy song song một kỳ công
Giữ cách làm cũ thêm một kỳ để đối chiếu số liệu, sau đó chuyển hẳn sang bảng công tập trung.

## Đồng bộ máy chấm công: nhân viên giữa các máy

Khi các máy đã về chung một tài khoản, việc **đồng bộ máy chấm công** làm từ phần mềm thay vì đi đến từng máy:

- **Tải người dùng từ máy về phần mềm** để ghép với hồ sơ nhân viên, tránh nhập lại.
- **Thêm, đổi tên, xóa người dùng trên máy ngay từ phần mềm**: nhân viên nghỉ việc được gỡ khỏi máy mà không cần người ở chi nhánh thao tác.
- **Sao chép nhân viên từ máy này sang máy khác**, đặc biệt hữu ích khi **mở chi nhánh mới**: đội ngũ chuyển từ cửa hàng cũ sang không phải nhập tay từng người.

Lưu ý: một số dòng máy chạy firmware rút gọn chỉ hỗ trợ một phần lệnh từ xa, có thể phải đăng ký vân tay hoặc khuôn mặt trực tiếp trên máy. Nên kiểm tra model trước khi triển khai đại trà.

## Xử lý nhân viên luân chuyển chi nhánh

Chuỗi cửa hàng thường xuyên điều người: thiếu ca ở chi nhánh này, mở điểm mới ở chi nhánh kia. Quy trình gợi ý:

1. **Điều chuyển tạm thời** (vài ngày, vài tuần): sao chép người dùng sang máy chi nhánh mới, giữ nguyên trên máy cũ. Nhân viên chấm ở đâu, bản ghi về đúng hồ sơ của họ vì dùng chung một mã.
2. **Điều chuyển hẳn**: cập nhật chi nhánh trong hồ sơ nhân viên, sao chép sang máy mới rồi xóa khỏi máy cũ từ phần mềm.
3. **Nhân viên làm nhiều nơi cố định** (quản lý vùng, kỹ thuật bảo trì): đưa lên máy của tất cả chi nhánh họ thường ghé, hoặc cho chấm công bằng điện thoại.

## Điểm không có máy: kết hợp chấm công điện thoại

Không phải điểm nào cũng cần một máy chấm công. Ki-ốt nhỏ, quầy trong siêu thị, công trình tạm, nhân viên giao hàng hay thị trường có thể [chấm công bằng điện thoại](/tinh-nang/cham-cong-khuon-mat-dien-thoai):

- Xác minh **khuôn mặt** khi chấm.
- Kiểm tra **vị trí GPS** hoặc **WiFi** của chi nhánh.
- **Khóa thiết bị**: chỉ điện thoại đã được quản lý duyệt mới chấm được, hạn chế chấm hộ.

| Loại điểm | Hình thức gợi ý |
|---|---|
| Cửa hàng, nhà hàng đông nhân viên | Máy chấm công khuôn mặt hoặc vân tay |
| Điểm bán nhỏ vài người | Điện thoại với WiFi cửa hàng |
| Công trình, điểm tạm | Điện thoại với GPS |
| Nhân viên đi lại giữa nhiều nơi | Điện thoại, hoặc có mặt trên nhiều máy |

Bản ghi từ máy và từ điện thoại đều về chung một bảng công, nên quản lý chuỗi cửa hàng chấm công không phải theo dõi hai hệ thống.

Cuối tháng, bảng công và bảng lương xuất được Excel theo từng chi nhánh để gửi kế toán.

Chưa có đủ máy cho các chi nhánh? SBOX nhận [lắp đặt máy chấm công tận nơi](/lap-dat-may-cham-cong) và kỹ thuật hỗ trợ kết nối qua Zalo 0973 024 042. Bạn có thể [đăng ký dùng thử miễn phí](/register), không cần thẻ thanh toán, kết nối thử một chi nhánh trước khi nhân rộng.

## Câu hỏi thường gặp

### Một tài khoản quản lý được bao nhiêu máy chấm công?
Một tài khoản quản lý được nhiều máy ở nhiều chi nhánh, mỗi máy gán cho một chi nhánh. Bảng công xem được theo từng chi nhánh hoặc toàn chuỗi.

### Các chi nhánh có cần IP tĩnh hoặc máy tính riêng không?
Không. Máy ZKTeco có ADMS tự kết nối ra máy chủ qua Internet bình thường, không cần IP tĩnh, mở port hay máy tính bật ở chi nhánh.

### Mở chi nhánh mới có phải nhập lại nhân viên vào máy không?
Không cần nhập tay từng người. Bạn sao chép nhân viên từ máy chi nhánh cũ sang máy mới ngay trên phần mềm; một số dòng máy firmware rút gọn có thể cần đăng ký lại vân tay, khuôn mặt trực tiếp.

### Nhân viên chấm ở chi nhánh khác thì công có bị tách ra không?
Không, nếu nhân viên dùng chung một mã trên toàn chuỗi. Bản ghi từ máy nào cũng về đúng hồ sơ của người đó và được cộng vào cùng một bảng công.