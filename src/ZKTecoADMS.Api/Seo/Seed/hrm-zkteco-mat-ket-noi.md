---
site: hrm
slug: may-cham-cong-zkteco-mat-ket-noi
title: Máy chấm công ZKTeco mất kết nối, không đẩy dữ liệu: nguyên nhân và cách khắc phục
metaTitle: Máy chấm công ZKTeco mất kết nối: 8 cách khắc phục
metaDescription: Máy chấm công ZKTeco không gửi dữ liệu lên phần mềm, báo offline, sai giờ, trùng mã nhân viên — nguyên nhân thường gặp và cách tự khắc phục từng bước.
keywords: máy chấm công mất kết nối, máy chấm công zkteco không kết nối, máy chấm công không đẩy dữ liệu, lỗi máy chấm công, máy chấm công sai giờ, cài đặt adms zkteco
summary: Tổng hợp các lỗi hay gặp khi máy chấm công ZKTeco kết nối phần mềm qua Internet (ADMS): mất mạng, sai địa chỉ máy chủ, sai giờ, sai múi giờ, trùng mã nhân viên, bộ nhớ đầy — và cách tự kiểm tra.
category: Máy chấm công
cover: /images/landing/screenshot-03.jpg
sortOrder: 45
---
Máy chấm công ZKTeco kết nối phần mềm qua **ADMS (Push / Cloud Server)** rất ổn định khi cài đúng. Khi máy báo mất kết nối hoặc bảng công không thấy dữ liệu mới, phần lớn nguyên nhân nằm ở vài điểm dưới đây — bạn có thể tự kiểm tra trước khi gọi kỹ thuật.

## 1. Máy mất mạng Internet

**Dấu hiệu**: biểu tượng mạng trên màn hình máy bị gạch, phần mềm báo "mất kết nối" từ một thời điểm.

**Kiểm tra**: cắm lại dây mạng, kiểm tra modem / switch có đèn tín hiệu ở cổng của máy; máy dùng WiFi thì kiểm tra mật khẩu WiFi có bị đổi. Máy dùng **IP tĩnh** cần đặt đúng gateway và DNS của modem hiện tại — thay modem mới thường làm sai các thông số này. Đơn giản nhất là bật **DHCP** để máy tự nhận IP.

Dữ liệu chấm trong lúc mất mạng vẫn lưu trong máy và sẽ **tự gửi bù** khi có mạng lại.

## 2. Sai địa chỉ máy chủ ADMS

Vào menu **Comm. / Cloud Server Setting** trên máy, kiểm tra địa chỉ máy chủ và cổng đúng như hướng dẫn của nhà cung cấp phần mềm. Lưu ý bật hoặc tắt **HTTPS** cho khớp, và tắt proxy nếu không dùng.

## 3. Máy chưa được thêm hoặc bị xóa trên phần mềm

Phần mềm nhận dữ liệu theo **số serial (SN)** của máy. Kiểm tra trong phần mềm máy có đúng SN không, có bị vô hiệu hóa hoặc gán sang cửa hàng khác không.

## 4. Sai giờ, sai múi giờ

**Dấu hiệu**: dữ liệu có nhưng lệch vài giờ, bị tính sang ngày khác, nhân viên bị báo đi trễ hàng loạt.

**Khắc phục**: chỉnh lại ngày giờ trên máy; đặt múi giờ **GMT+7**. Phần mềm có thể gửi lệnh đồng bộ giờ cho máy. Pin CMOS yếu khiến máy mất giờ mỗi khi cúp điện — cần thay pin.

## 5. Trùng hoặc sai mã nhân viên

**Dấu hiệu**: có bản ghi nhưng không ghép được với nhân viên nào, hoặc ghép nhầm người.

**Khắc phục**: mã người dùng trên máy (PIN / User ID) phải **ghép đúng** với hồ sơ nhân viên trên phần mềm. Khi dùng nhiều máy, giữ một mã thống nhất cho một người ở tất cả các máy.

## 6. Bộ nhớ chấm công đầy

Máy đời cũ có dung lượng bản ghi giới hạn. Khi đầy, máy có thể không ghi thêm hoặc ghi đè. Sau khi chắc chắn dữ liệu đã lên phần mềm, có thể xóa bớt bản ghi cũ trên máy — **cẩn thận** vì lệnh xóa toàn bộ dữ liệu trên một số dòng máy xóa luôn cả người dùng và vân tay.

## 7. Dòng máy chỉ hỗ trợ một phần lệnh từ xa

Một số dòng máy giá rẻ chạy firmware rút gọn: vẫn gửi dữ liệu chấm công lên phần mềm nhưng **không nhận một số lệnh từ xa** như đăng ký vân tay từ xa, tải toàn bộ danh sách người dùng. Với dòng máy này, đăng ký vân tay trực tiếp trên máy; người dùng mới thêm trên máy sẽ tự được đẩy lên phần mềm.

## 8. Tường lửa hoặc nhà mạng chặn

Một số mạng doanh nghiệp chặn kết nối ra ngoài trừ cổng web thông dụng. Nhờ IT mở kết nối ra địa chỉ máy chủ ADMS hoặc dùng cổng HTTPS.

## Theo dõi trạng thái máy trên phần mềm

Với [SBOX HRM](/tinh-nang/phan-mem-cham-cong-zkteco), mỗi máy hiện **trạng thái kết nối, thời điểm gửi dữ liệu gần nhất**, số người dùng và số bản ghi; trang Thiết lập báo ngay khi có máy mất kết nối để bạn xử lý trước khi ảnh hưởng tới bảng công. Kỹ thuật SBOX hỗ trợ kiểm tra từ xa qua Zalo 0973 024 042.

Xem thêm: [Kết nối máy chấm công ZKTeco qua Internet](/bai-viet/ket-noi-may-cham-cong-zkteco-qua-internet).

[Đăng ký dùng thử SBOX HRM miễn phí](/register) — không cần thẻ thanh toán, đội kỹ thuật hỗ trợ kết nối máy chấm công và cấu hình ca, lương qua Zalo 0973 024 042.

## Câu hỏi thường gặp

### Máy chấm công mất mạng có mất dữ liệu không?
Không. Máy lưu bản ghi trong bộ nhớ khi mất mạng và tự gửi bù lên phần mềm khi kết nối lại, miễn là bộ nhớ máy chưa đầy.

### Vì sao dữ liệu chấm công bị lệch giờ?
Thường do máy sai ngày giờ hoặc sai múi giờ. Đặt múi giờ GMT+7, chỉnh giờ đúng và thay pin nếu máy mất giờ sau mỗi lần cúp điện.

### Đổi modem mới thì máy chấm công có cần cài lại không?
Nếu máy đặt IP tĩnh, cần chỉnh lại IP, gateway, DNS cho phù hợp modem mới hoặc chuyển sang DHCP. Địa chỉ máy chủ ADMS không cần đổi.
