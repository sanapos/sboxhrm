---
site: hrm
slug: mau-bang-luong-excel
title: Mẫu bảng lương Excel 2026 tự tính BHXH, thuế TNCN (tải miễn phí)
metaTitle: Mẫu bảng lương Excel 2026 tự tính BHXH, thuế TNCN
metaDescription: Tải miễn phí mẫu bảng lương Excel 2026 có công thức sẵn: lương ngày công, tăng ca, phụ cấp, BHXH 10,5%, thuế TNCN 5 bậc, giảm trừ 15,5 triệu. Kèm hướng dẫn từng cột.
keywords: mẫu bảng lương excel, mẫu bảng lương 2026, bảng lương excel có công thức, file tính lương excel, mẫu bảng thanh toán tiền lương, bảng lương nhân viên
summary: Mẫu bảng lương Excel 2026 có sẵn công thức tính lương theo ngày công, tăng ca, bảo hiểm và thuế TNCN theo biểu 5 bậc. Bài viết giải thích từng cột để bạn sửa theo quy chế lương của doanh nghiệp.
category: Tính lương
cover: /images/landing/screenshot-05.jpg
sortOrder: 60
---
Bảng lương là tài liệu doanh nghiệp nào cũng phải làm hằng tháng, và cũng là nơi dễ sai nhất: sai ngày công, quên trừ tạm ứng, tính thuế TNCN nhầm bậc. Mẫu bảng lương Excel 2026 dưới đây đã có sẵn công thức theo quy định mới nhất về giảm trừ gia cảnh và biểu thuế — bạn chỉ cần nhập số liệu.

**[Tải mẫu bảng lương Excel 2026 miễn phí](/tai-lieu)** (file .xlsx, mở được bằng Excel, Google Sheets).

## Cấu trúc file

File gồm hai sheet:

1. **Thiết lập** — các thông số dùng chung: ngày công chuẩn, giảm trừ bản thân, giảm trừ người phụ thuộc, tỷ lệ BHXH – BHYT – BHTN, mức lương đóng bảo hiểm tối đa, hệ số tăng ca. Khi luật thay đổi, chỉ cần sửa ở đây.
2. **Bảng lương** — mỗi nhân viên một dòng, các ô màu vàng là ô nhập, các ô còn lại tự tính.

## Giải thích từng cột

| Cột | Ý nghĩa | Cách tính |
|---|---|---|
| Lương thỏa thuận | Lương ghi trong hợp đồng | Nhập |
| Lương đóng BH | Mức lương làm căn cứ đóng bảo hiểm | Nhập |
| Ngày công thực tế | Số ngày đi làm trong tháng | Nhập (lấy từ bảng chấm công) |
| Giờ tăng ca | Tổng giờ tăng ca ngày thường | Nhập |
| Phụ cấp chịu thuế | Phụ cấp trách nhiệm, chuyên cần… | Nhập |
| Phụ cấp không chịu thuế | Ăn giữa ca trong mức miễn thuế | Nhập |
| Lương theo công | Lương thỏa thuận ÷ ngày công chuẩn × ngày công thực tế | Tự tính |
| Tiền tăng ca | Lương giờ × giờ tăng ca × 150% | Tự tính |
| BHXH / BHYT / BHTN | 8% / 1,5% / 1% lương đóng BH (có trần) | Tự tính |
| Giảm trừ gia cảnh | 15,5 triệu + 6,2 triệu × số người phụ thuộc | Tự tính |
| Thu nhập tính thuế | Tổng thu nhập chịu thuế − bảo hiểm − giảm trừ | Tự tính |
| Thuế TNCN | Biểu lũy tiến 5 bậc | Tự tính |
| Thực lĩnh | Tổng thu nhập − bảo hiểm − thuế − tạm ứng | Tự tính |

## Công thức thuế TNCN trong file

File dùng cách tính rút gọn theo biểu lũy tiến 5 bậc (thu nhập tính thuế theo tháng):

| Thu nhập tính thuế / tháng | Thuế suất | Công thức rút gọn |
|---|---|---|
| Đến 10 triệu | 5% | TN × 5% |
| Trên 10 – 30 triệu | 10% | TN × 10% − 0,5 triệu |
| Trên 30 – 60 triệu | 20% | TN × 20% − 3,5 triệu |
| Trên 60 – 100 triệu | 30% | TN × 30% − 9,5 triệu |
| Trên 100 triệu | 35% | TN × 35% − 14,5 triệu |

Phần tiền tăng ca được trả cao hơn so với giờ làm bình thường được **miễn thuế**, nên file chỉ đưa phần lương giờ thường của tiền tăng ca vào thu nhập chịu thuế. Xem giải thích chi tiết ở bài [cách tính thuế TNCN từ tiền lương](/bai-viet/cach-tinh-thue-tncn-tu-tien-luong).

## Ví dụ

Nhân viên lương thỏa thuận 12 triệu, đóng bảo hiểm trên 8 triệu, đi làm đủ 26 công, phụ cấp 1 triệu, ăn trưa 730.000 đ, có 1 người phụ thuộc:

- Tổng thu nhập: 12.000.000 + 1.000.000 + 730.000 = 13.730.000 đ
- Bảo hiểm: 8.000.000 × 10,5% = 840.000 đ
- Giảm trừ: 15.500.000 + 6.200.000 = 21.700.000 đ
- Thu nhập tính thuế: 13.000.000 − 840.000 − 21.700.000 < 0 → **không phải nộp thuế**
- Thực lĩnh: 13.730.000 − 840.000 = **12.890.000 đ**

Với mức giảm trừ mới, phần lớn nhân viên có thu nhập dưới khoảng 17 triệu/tháng và không có người phụ thuộc vẫn chưa phải nộp thuế TNCN.

## Những lỗi hay gặp khi làm bảng lương Excel

- **Copy công thức sai dòng** khi thêm nhân viên mới giữa bảng.
- **Nhập tay ngày công** từ bảng chấm công — dễ lệch với dữ liệu thật. Xem [mẫu bảng chấm công Excel](/bai-viet/mau-bang-cham-cong-excel).
- **Quên cập nhật** mức giảm trừ, lương cơ sở khi luật thay đổi.
- **Không lưu lịch sử**: sửa đè file tháng trước, không đối chiếu được khi nhân viên thắc mắc.

## Khi nào nên chuyển sang phần mềm tính lương?

Excel phù hợp khi dưới khoảng 20 nhân viên và ít biến động. Khi có nhiều ca, nhiều chi nhánh, tăng ca thường xuyên, [phần mềm tính lương](/tinh-nang/phan-mem-tinh-luong) lấy thẳng dữ liệu từ máy chấm công, đơn tăng ca, đơn nghỉ phép đã duyệt và gửi phiếu lương cho từng nhân viên qua app — tiết kiệm nhiều ngày công mỗi tháng.

[Đăng ký dùng thử SBOX HRM miễn phí](/register) — không cần thẻ thanh toán, đội kỹ thuật hỗ trợ kết nối máy chấm công và cấu hình ca, lương qua Zalo 0973 024 042.

## Câu hỏi thường gặp

### Mẫu bảng lương này dùng được cho năm 2026 không?
Có. File đã cập nhật giảm trừ bản thân 15,5 triệu, người phụ thuộc 6,2 triệu và biểu thuế lũy tiến 5 bậc. Bạn vẫn nên kiểm tra văn bản mới nhất trước khi chi lương.

### Có mở được bằng Google Sheets không?
Được. Tải file .xlsx rồi mở bằng Google Sheets hoặc tải lên Google Drive; các công thức vẫn hoạt động.

### Doanh nghiệp tính lương theo 26 công cố định thì sửa ở đâu?
Sửa ô Ngày công chuẩn ở sheet Thiết lập. Nếu tính theo ngày công thực tế của từng tháng, đổi ô này mỗi tháng.
