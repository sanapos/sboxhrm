# QR ngân hàng in ra quét không được + công tắc QR nổi (04/11/2026)

Chưa commit, chưa deploy. Chưa thử trên giấy thật.

## Nguyên nhân (đã tái hiện bằng raster GS v 0 + giải mã zxing-cpp)
`posQrPngBytes` chia cạnh cho số ô thành số lẻ (208/49 = 4,24 điểm), rồi làm tròn vị trí và nới `ceil + 0,5`
→ ô đen 6 điểm, ô trắng 2–3 điểm. Thêm hai lỗi căn lưới ở `_renderReceiptImage` (lệch nửa điểm + chiều cao lẻ)
ra cạnh xám, ngưỡng 160 biến thành đen. Thanh trượt cỡ QR trong trình soạn chỉ 100–220 nên trình biên dịch
luôn nâng lên 240 — tức gần như mọi bill đều ở cỡ tệ nhất.

Chuỗi VietQR không sai: trùng từng ký tự với mã đọc từ ảnh img.vietqr.io.

## Đo được (chuỗi 131 byte, 49 ô; mô phỏng nở nét là mô phỏng, không phải giấy thật)
| Trường hợp | Ô đen/trắng (điểm) | Giải mã ảnh số | Mô phỏng nở nét 15% (số lần đọc được / 10) |
| Cũ K58 cỡ 240 | ~6 / 2–3 | LỖI cả 4 độ lệch | - |
| Cũ K80 cỡ 240 | 6 / 2–3 | 3/4 độ lệch đọc được, 1 lỗi | 0–1 |
| Mới K58, K80 cỡ 300 | 5 / 5 | đọc được | 10 |

## Sửa
- flutter_client + flutter_pos: `pos_einvoice_qr.dart` (ô đúng số nguyên điểm, viền 4 ô), cỡ VietQR tối thiểu 300.
- flutter_client: `pos_thermal_bitmap.dart` bám lưới điểm, chiều cao chẵn.
- flutter_pos: thêm luồng sinh VietQR tại máy (trước đó luôn tải ảnh compact2 có logo rồi co, ô ~3,2 điểm).

## Công tắc
`showPaymentQrOverlay` (mặc định bật), lưu `ExtraJson.vietQr.showOverlay` + prefs; màn «Tài khoản nhận tiền».
Đã thử trên web QA: bật → QR nổi; tắt → không nổi, vẫn có QR trong màn thanh toán + «Phóng to mã QR».
Chưa thử: màn phụ khi tắt, Tingee khi tắt, mobile, flutter_pos trên máy.
