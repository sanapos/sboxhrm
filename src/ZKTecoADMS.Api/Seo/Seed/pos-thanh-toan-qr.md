---
site: pos
slug: thanh-toan-qr-chuyen-khoan-tu-dong-doi-soat
title: Thanh toán QR chuyển khoản tự động đối soát: không còn nhìn điện thoại chủ quán
metaTitle: Thanh toán QR chuyển khoản tự động đối soát
metaDescription: Thu tiền chuyển khoản bằng mã QR và tự động đối soát với đơn hàng: tránh nhầm giao dịch, ảnh chuyển khoản giả, giảm thất thoát. Nguyên lý và lưu ý triển khai.
keywords: thanh toán qr chuyển khoản, đối soát chuyển khoản tự động, mã qr thanh toán quán, tingee, nhận biết chuyển khoản, chống giả ảnh chuyển khoản, phần mềm bán hàng thanh toán qr
summary: Khách chuyển khoản qua QR nhưng nhân viên không chắc tiền đã về — đó là nguồn thất thoát và tranh cãi. Bài viết giải thích cách tự động nhận biết giao dịch và khớp với đơn hàng, và những điểm cần cấu hình.
category: Thiết bị bán hàng
cover: /images/landing/pos/pos-checkout.jpg
sortOrder: 47
---
Khách quét mã QR trả tiền rất tiện, nhưng quán nào cũng gặp: **khách đưa ảnh chuyển khoản giả**, nhân viên **không chắc tiền đã về tài khoản**, hoặc chủ quán phải mở ứng dụng ngân hàng liên tục để đối chiếu từng bill. Đối soát tự động giải quyết các vấn đề này.

## Vấn đề của cách làm thủ công

| Tình huống | Hậu quả |
|---|---|
| Khách đưa màn hình “đã chuyển” | Có thể là ảnh giả, tiền chưa về |
| Nhân viên tự bấm “đã thanh toán” | Thất thoát nếu tiền không về, hoặc nhận nhầm tiền của đơn khác |
| Nhiều đơn chuyển khoản cùng lúc | Khó khớp đúng đơn, nhất là giờ cao điểm |
| Chủ quán xem tin nhắn ngân hàng | Mất thời gian, dễ sót giao dịch |

## Cách đối soát tự động hoạt động

1. Khi thanh toán, hệ thống sinh **mã QR kèm nội dung/mã đơn** riêng cho hóa đơn đó.
2. Khách quét QR và chuyển khoản đúng số tiền.
3. Cổng nhận tiền (ví dụ **Tingee**) nhận biến động số dư và **gửi thông báo** về hệ thống.
4. Hệ thống **khớp giao dịch với đơn đang chờ** và xác nhận thanh toán, trên màn hình thu ngân hiện báo đã nhận tiền.
5. Mọi thông báo được lưu để tra cứu khi có tranh cãi.

SBOX POS có sẵn luồng đơn chờ chuyển khoản, xác nhận qua thông báo từ cổng thanh toán hoặc xác nhận thủ công khi cần.

## Lợi ích cho cửa hàng

- **Chống giả ảnh chuyển khoản**: chỉ khi có tiền thật về thì đơn mới được xác nhận.
- **Giảm sai sót** nhầm đơn, nhận thiếu tiền.
- **Nhanh hơn**: không phải đợi nhân viên kiểm tra tài khoản.
- **Đối chiếu cuối ca dễ**: tiền chuyển khoản trong ca khớp với phiếu thu, xem [quản lý ca thu ngân và chốt ca](/bai-viet/quan-ly-ca-thu-ngan-chot-ca).

## Việc cần chuẩn bị

1. **Tài khoản ngân hàng của quán** (nên dùng tài khoản doanh nghiệp hoặc hộ kinh doanh).
2. **Đăng ký dịch vụ thông báo biến động số dư** với cổng thanh toán được tích hợp.
3. **Cấu hình trong phần mềm** theo hướng dẫn, kiểm tra bằng một giao dịch nhỏ.
4. **Quy trình dự phòng** khi mất mạng hoặc cổng bị gián đoạn: xác nhận thủ công có kiểm tra tài khoản và ghi lý do.

Hãy trao đổi với đội ngũ hỗ trợ để được hướng dẫn cấu hình đúng; quy trình đăng ký phụ thuộc ngân hàng và nhà cung cấp cổng thanh toán.

## Hiển thị QR cho khách

Mã QR có thể hiển thị trên **màn hình phụ hướng về khách** để khách quét thanh toán dễ dàng, xem [máy POS Android màn hình phụ](/bai-viet/may-pos-android-man-hinh-phu-cho-cua-hang). Hóa đơn in cũng có thể kèm mã QR cho khách thanh toán sau.

## Lưu ý về kế toán và thuế

- Tiền chuyển khoản vào tài khoản của cơ sở kinh doanh được ghi nhận như doanh thu bình thường; đối soát chuyển khoản nằm trong sổ quỹ cùng tiền mặt.
- Cơ sở thuộc diện xuất hóa đơn điện tử nên xem [hóa đơn điện tử từ máy tính tiền](/bai-viet/hoa-don-dien-tu-khoi-tao-tu-may-tinh-tien).
- Hãy tham khảo kế toán hoặc cơ quan thuế về nghĩa vụ cụ thể của bạn.

## Áp dụng cho từng loại hình

- **Quán ăn, cà phê**: chuyển khoản tại quầy hoặc tại bàn, xem [phần mềm quản lý nhà hàng](/tinh-nang/phan-mem-quan-ly-nha-hang).
- **Quán bi-a, karaoke, homestay**: thanh toán cuối phiên, số tiền lớn nên càng cần đối soát tự động, xem [quán bi-a karaoke](/tinh-nang/phan-mem-quan-ly-quan-bida-karaoke).
- **Cửa hàng bán lẻ, bán online**: đơn có thể chuyển khoản trước khi giao.

[Đăng ký dùng thử SBOX POS](/register) và xem luồng đơn chờ chuyển khoản trên màn bán.

## Câu hỏi thường gặp

### Nếu khách chuyển sai số tiền thì sao?
Hãy kiểm tra số tiền thực nhận trong thông báo giao dịch trước khi giao hàng hoặc trả bàn; nếu thiếu thì yêu cầu khách chuyển thêm, nếu thừa thì hoàn lại, và ghi chú rõ trong đơn.

### Mất mạng có thanh toán chuyển khoản được không?
Giao dịch vẫn về tài khoản nhưng phần mềm chưa nhận được thông báo; hãy dùng quy trình xác nhận thủ công có đối chiếu.

### Có cần mở tài khoản riêng không?
Nên dùng tài khoản riêng của cơ sở kinh doanh để đối chiếu rõ ràng, không lẫn tiền cá nhân.
