---
site: hrm
slug: mau-bang-cham-cong-excel
title: Mẫu bảng chấm công Excel theo tháng tự tính tổng công (tải miễn phí)
metaTitle: Mẫu bảng chấm công Excel theo tháng, tự cộng công
metaDescription: Tải miễn phí mẫu bảng chấm công Excel theo tháng: tự đổi thứ trong tuần, ký hiệu X, H, P, L, Ô, N, tự cộng công thực tế, phép, lễ và tổng công hưởng lương.
keywords: mẫu bảng chấm công, mẫu bảng chấm công excel, bảng chấm công theo tháng, file chấm công excel, cách làm bảng chấm công, ký hiệu chấm công
summary: Mẫu bảng chấm công Excel 31 ngày tự hiện thứ trong tuần khi đổi tháng, có danh sách ký hiệu chọn sẵn và công thức cộng tổng công hưởng lương — kèm hướng dẫn và các lưu ý khi chấm công thủ công.
category: Chấm công
cover: /images/landing/screenshot-04.jpg
sortOrder: 58
---
Bảng chấm công là căn cứ để tính lương, đóng bảo hiểm và giải quyết tranh chấp với người lao động. Một bảng chấm công tốt cần rõ ràng ký hiệu, cộng đúng tổng công và lưu được lâu dài. Dưới đây là mẫu bảng chấm công Excel theo tháng bạn có thể dùng ngay.

**[Tải mẫu bảng chấm công Excel miễn phí](/tai-lieu)**

## Mẫu có gì?

- Nhập **tháng, năm** ở đầu bảng — hàng tiêu đề tự đổi ngày và thứ (T2…CN), tháng 30 ngày tự ẩn ngày 31.
- 20 dòng nhân viên, thêm dòng bằng cách sao chép dòng cuối.
- Ô ngày có **danh sách chọn ký hiệu** để tránh gõ sai.
- Cột tổng tự tính: công thực tế, phép, lễ, ốm, không lương, tổng công hưởng lương.

## Bộ ký hiệu chấm công

| Ký hiệu | Ý nghĩa | Tính công |
|---|---|---|
| X | Đi làm đủ ngày | 1 công |
| H | Làm nửa ngày | 0,5 công |
| P | Nghỉ phép năm có lương | 1 công hưởng lương |
| L | Nghỉ lễ, Tết | 1 công hưởng lương |
| Ô | Nghỉ ốm (hưởng chế độ BHXH) | Không tính lương doanh nghiệp |
| N | Nghỉ không lương | 0 |

Bạn có thể thêm ký hiệu riêng (ví dụ CT – công tác, TC – tăng ca) và thêm cột đếm tương ứng bằng hàm COUNTIF.

## Công thức chính

- Công thực tế = `COUNTIF(dải ngày,"X") + COUNTIF(dải ngày,"H") × 0,5`
- Tổng công hưởng lương = công thực tế + phép + lễ
- Thứ trong tuần = `CHOOSE(WEEKDAY(DATE(năm,tháng,ngày)),"CN","T2",…)`

Tổng công hưởng lương là con số đưa vào [bảng lương](/bai-viet/mau-bang-luong-excel) để tính lương theo ngày công.

## Lưu ý khi chấm công thủ công

1. **Ghi ngay trong ngày**, không dồn cuối tuần — dễ nhớ nhầm.
2. **Có người xác nhận**: trưởng bộ phận ký xác nhận bảng chấm công cuối tháng.
3. **Lưu kèm chứng từ**: đơn xin nghỉ, đơn tăng ca, giấy đi công tác.
4. **Thống nhất quy định** đi trễ, về sớm bao nhiêu phút thì tính nửa công — ghi rõ trong nội quy.
5. **Không sửa đè**: mỗi tháng một file hoặc một sheet riêng.

## Hạn chế của bảng chấm công Excel

Chấm công thủ công phụ thuộc vào người ghi: dễ nể nang, khó kiểm tra giờ vào – ra thực tế, không biết ai đi trễ bao nhiêu phút. Khi có nhiều ca hoặc nhiều chi nhánh, tổng hợp cuối tháng mất rất nhiều thời gian.

Giải pháp là dùng [máy chấm công ZKTeco kết nối Internet](/tinh-nang/phan-mem-cham-cong-zkteco) hoặc [chấm công khuôn mặt bằng điện thoại](/tinh-nang/cham-cong-khuon-mat-dien-thoai): giờ vào – ra được ghi tự động, phần mềm tính sẵn công, đi trễ, tăng ca theo từng ca làm việc và xuất bảng công Excel đúng định dạng bạn cần.

[Đăng ký dùng thử SBOX HRM miễn phí](/register) — không cần thẻ thanh toán, đội kỹ thuật hỗ trợ kết nối máy chấm công và cấu hình ca, lương qua Zalo 0973 024 042.

## Câu hỏi thường gặp

### Bảng chấm công có bắt buộc phải lưu không?
Doanh nghiệp nên lưu bảng chấm công cùng bảng lương vì đây là căn cứ tính lương, đóng bảo hiểm và giải quyết khi có tranh chấp lao động hoặc khi cơ quan chức năng kiểm tra.

### Nghỉ ốm có tính lương không?
Ngày nghỉ ốm thường do cơ quan BHXH chi trả chế độ ốm đau (khi người lao động tham gia BHXH và có giấy tờ hợp lệ), doanh nghiệp không trả lương cho ngày đó trừ khi quy chế có quy định khác.

### Làm nửa ngày thì ghi thế nào?
Dùng ký hiệu H (0,5 công). Nếu doanh nghiệp tính theo giờ, nên chấm công theo giờ vào – ra thay vì theo ngày.
