# Môi trường test local — kho (SBOX POS)

Kiểm thử **logic** và **giao diện** 5 chức năng kho trên máy cá nhân, không đụng production:

| Chức năng | Màn (module) | Logic được kiểm |
|---|---|---|
| Nhập hàng NCC | `PosPurchaseReceipts` | phiếu tạm không cộng kho · giá vốn bình quân · giảm giá đầu phiếu · quy đổi Thùng → Lon · công nợ NCC · sổ quỹ khi trả tiền · không hủy được phiếu đã thanh toán · hủy phiếu hoàn tồn / giá vốn / công nợ |
| Trả hàng NCC | `PosPurchaseReturns` | trừ tồn · giảm công nợ · hủy phiếu hoàn đúng công nợ (kể cả khi đã hết nợ) |
| Xuất hủy | `PosDamageIssues` | trừ tồn theo giá vốn · chặn xuất vượt tồn · báo cáo «chi phí xuất hủy» · hủy phiếu |
| Xuất dùng nội bộ | `PosInternalUseIssues` | trừ tồn · báo cáo «xuất nội bộ» · hủy phiếu |
| Kiểm kho | `PosStockCounts` | phiếu tạm không đổi tồn · cân bằng kho · chênh lệch · báo cáo «hao hụt kiểm kê» · hủy phiếu |

Mỗi lần chạy tạo **hàng hóa + nhà cung cấp riêng** (tên bắt đầu `KT<ngày giờ>`), nên chạy lại bao nhiêu lần cũng được; script từ chối chạy nếu API không phải `localhost`.

## 1. Chuẩn bị (một lần)

- PostgreSQL local có CSDL thử (mặc định `sbox_uidemo`) và tài khoản cửa hàng thử trong đó.
- .NET 8 SDK, Flutter, Python 3, Node 18+, Google Chrome.
- `cd tools/local-test && npm install`

Tài khoản test đặt bằng **biến môi trường** (không ghi vào repo):

```bash
export SBOX_TEST_STORE=quandemoui
export SBOX_TEST_USER=<email>
export SBOX_TEST_PASS=<mật khẩu>
# hoặc: export SBOX_TEST_CRED_FILE=/đường/dẫn/file  (nội dung: «email mật_khẩu», để NGOÀI repo)
```

## 2. Bật môi trường

Mỗi lệnh chạy ở một cửa sổ riêng:

```bash
bash tools/local-test/start-api.sh
```
API ở `http://localhost:7199`. Script build ra thư mục tạm riêng, nên không khóa DLL của API khác đang chạy.

```bash
FLUTTER=flutter bash tools/local-test/build-web.sh
```

```bash
python tools/local-test/web_proxy.py 8190 http://localhost:7199
```
Mở web tại `http://localhost:8190`.

Đổi cổng / CSDL: `SBOX_API_PORT`, `SBOX_TEST_DB`, `SBOX_WEB_PORT`.

## 3. Chạy kiểm thử

```bash
cd tools/local-test
SBOX_API=http://localhost:7199 node warehouse-e2e.js
```
In bảng ĐẠT / LỖI theo nhóm, mã thoát ≠ 0 khi có lỗi; kết quả lưu ở `out/warehouse-e2e.json`.

```bash
SBOX_API=http://localhost:7199 node cashbook-e2e.js
```
Sổ quỹ / thu chi: phiếu thu tự sinh vào đúng quỹ (Tiền mặt · Tingee · tiền vào tài khoản ngân hàng), số dư quỹ, tồn đầu – cuối kỳ của báo cáo Sổ quỹ, thu chi theo ngày / phương thức khớp tổng, chặn xóa phiếu tự động, hủy đơn hoàn phiếu thu. Kết quả ở `out/cashbook-e2e.json`.

```bash
SBOX_API=http://localhost:7199 SBOX_WEB=http://localhost:8190 node ui-shots.js
```
Chụp 5 màn × (điện thoại: danh sách · chi tiết · tạo phiếu, máy tính: danh sách · chi tiết), mở `out/ui/index.html` để xem. Chỉ một màn: `SBOX_UI_ONLY=PosStockCounts`.

Test tự động phía máy chủ (CSDL tạm, tự xóa):

```bash
cd src
dotnet test ZKTecoADMS.Tests/ZKTecoADMS.Tests.csproj --filter "FullyQualifiedName~Pos"
```
Nếu API khác đang khóa DLL: thêm `-o "$TEMP/sbox-tests-out"` và đặt `SBOX_TEST_PG=<chuỗi kết nối>` (khi build ra thư mục khác, test không tự tìm thấy appsettings).

## Ghi chú

- Ảnh / kết quả nằm trong `out/` (không đưa lên git).
- Thêm kịch bản: dùng `lib/api.js` (`login`, `client`, `Report.eq/check/must`).
