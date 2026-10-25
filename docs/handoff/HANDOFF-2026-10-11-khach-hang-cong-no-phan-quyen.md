# Bàn giao — Phân quyền, chấm công / lương, tổng quan, chi nhánh, khách hàng & công nợ (11/10/2026)

Người nhận: một phiên Claude khác. Trả lời người dùng **bằng tiếng Việt**.
Code đã xong, đã commit, đã có trên `origin` (nhánh `fix/tingee-agent-scope-deploy`). **Chưa deploy** phần lớn (xem bảng).
Người dùng dặn «xong không build»: **không push / deploy / build bản phát hành khi chưa được yêu cầu.**

## 1. Các commit của phiên này (cũ → mới)

| Commit | Nội dung | Deploy |
|---|---|---|
| `51455073` | Báo cáo nhân sự khớp bảng lương, đếm ngày nghỉ, số lẻ | **Đã deploy** sboxhrm |
| `0765b8e9` | Quyền mặc định theo mẫu gói, khóa API quyền cũ, khóa TK → đăng xuất | **Đã deploy** sboxhrm |
| `93d9b27d` | Thu hồi quyền dư cũ; Giám đốc theo bảng quyền; chốt lương cần quyền Duyệt; Kế toán xem cả cửa hàng; Thu ngân / Phục vụ / User tự phục vụ; xóa màn Quản lý người dùng cũ | Chưa — API + web + app |
| `edbc66f6` | Tạo bảng `__SchemaPatches` trước khi chạy patch; cột `PenaltySettings.AutoApproveHours`; ngày phiếu thu chi = giờ VN (migration 1 lần, chỉ dịch dòng ≈ CreatedAt) | Chưa — API |
| `04e27173` | Chế độ «chấm bất kỳ trong ca»: bảng lương đủ công; check-in sau giờ ca; lịch sử thao tác giờ VN | Chưa — API + web + app |
| `386bb0c5` | Mở app không nhảy menu / hóa đơn (cache quyền + gói) — flutter_client + flutter_pos | Chưa — web + app + APK POS |
| `f7e558ed` | Báo cáo chi nhánh khớp Lãi lỗ; quản lý chỉ sửa chi nhánh mình; 6 báo cáo POS đọc phiếu thu chi theo giờ VN | Chưa — **phải deploy cùng `edbc66f6`** |
| `09958637` | Tổng quan theo gói (POS / HRM / cả hai): chuyên cần đúng, theo chi nhánh; che giá vốn | Chưa — API + web + app |
| `293b46be` | «Nhân viên hôm nay» theo chấm công thực tế | Chưa — API + web + app |
| `91623d6b` | Khách hàng: lọc sinh nhật / lâu không mua / trạng thái / sắp xếp máy chủ, chặn trùng SĐT, ngừng hoạt động, sản phẩm & điểm theo khách; NCC: lịch sử có lần trả tiền | Chưa — API + web + app |
| `ad628cbf` | Sổ đối chiếu công nợ khách / NCC (bảng `PosDebtLedgerEntries`); trả nợ NCC gộp nhiều phiếu (FIFO); thu nợ tính cả VAT / phụ thu / phí giao; không tạo trùng danh mục «Nhập hàng»; SboxDataTable không tràn cột | Chưa — API + web + app |
| `3d6f8a65` | Hạng thành viên theo tổng mua (thiết lập trong «Tích điểm & đổi điểm», lọc / nhãn hạng, tiến độ lên hạng). Commit do phiên song song tạo nhưng chứa đúng phần việc phiên này | Chưa — API + web + app |

Bản vá CSDL tự chạy khi API khởi động (idempotent, trong `src/ZKTecoADMS.Infrastructure/SchemaPatches/`):
`CashTransactionDateVnLocal.sql` (1 lần), `PosDebtLedger.sql` (tạo bảng + dòng «Số dư đầu» = công nợ hiện tại, 1 lần),
`PosLoyaltyTiers.sql` (cột `LoyaltyTiersJson`).

## 2. Khi người dùng yêu cầu deploy
- Chỉ deploy **sboxhrm 103.133.224.176** (container `zkteco_postgres` / `zkteco_api` / `zkteco_flutter`).
  **Không** deploy sboxpos 103.133.225.67 (phiên này không có quyền DB ở đó).
- SSH chỉ bằng khóa `"/c/Users/TH DECOR/.ssh/sbox_deploy_ed25519"`. Không dùng mật khẩu người dùng gửi trong chat;
  không in token Codemagic / API key / secret production.
- API: `git archive HEAD:src` → scp → `_deploy_api.sh`, gắn tag rollback trước. Build từ **commit sạch** (git worktree),
  không build từ thư mục làm việc (phiên khác đang sửa dở file KDS).
- Web: **bắt buộc** `scripts/deploy-flutter-web-only.ps1 -Target sboxhrm` (có render trang chủ SEO).
- DB production chỉ đọc khi kiểm tra: đầu câu lệnh `SET default_transaction_read_only = on;`.
- Sau deploy nên kiểm tra: bảng `__SchemaPatches` có `CashTransactionDateVnLocal`, `PosDebtLedgerOpening`;
  `PosDebtLedgerEntries` có dòng Opening cho 2 NCC đang nợ (tổng 366.817.719đ tại thời điểm kiểm tra).

## 3. Đã kiểm thử
- Backend: **666/666** test xUnit (`dotnet test ZKTecoADMS.Tests -o <thư mục tạm>`), gồm mới:
  `PosDebtLedgerTests` (ghi sổ bán / thu nợ / trả hàng, đầu kỳ – cuối kỳ, trả gộp NCC FIFO + phiếu chi không trùng mã),
  `PosCustomerTierTests`, `PosCustomerListTests`, `BranchReportTests`, `DashboardAttendanceTrendsTests`.
- Flutter widget test (điện thoại 390px + máy tính, không tràn): `pos_customers_ui_test.dart`,
  `pos_debt_statement_ui_test.dart`, `pos_loyalty_tiers_ui_test.dart` — chạy 3 lần liên tiếp đều qua.
  Ảnh chụp: đặt `SBOX_SHOT_DIR`. Lệnh: `FLUTTER_ROOT=C:/FlutterSDK LOCALAPPDATA="E:\SBOX-SDK\dart-local" C:/FlutterSDK/bin/flutter.bat test ...`
- `flutter analyze` sạch lỗi cho các file đã sửa.
- **Chưa** thử trên web / máy thật sau deploy.

## 4. Lưu ý kỹ thuật
- Sổ công nợ chỉ ghi **từ khi cập nhật chạy**; trước đó chỉ có 1 dòng «Số dư đầu». Nếu số dư sổ lệch công nợ hiện tại,
  màn sổ đối chiếu hiện cảnh báo. Mọi chỗ đổi `PosCustomer.CurrentDebt` / `PosSupplier.CurrentDebt` mới phải gọi
  `PosDebtLedger.Add(...)` (`src/ZKTecoADMS.Api/Controllers/PosDebtLedger.cs`).
- `CashTransaction.TransactionDate` giờ là **giờ VN**; `CreatedAt` / `SaleDate` / `PaidAt` vẫn là UTC.
- Entry `MemoryCache` của API phải đặt `Size = 1` (thiếu là lỗi 500 mọi request).
- Hạng thành viên v1 chỉ phân loại + ghi chú ưu đãi, **chưa** tự giảm giá / nhân điểm (nhân điểm phải sửa đồng bộ
  `CalcPointsEarn` ở `PosSalesController.Draft.cs` và `RestorePointsOnReturnVoidAsync`).
- Phiên khác đang sửa dở (chưa commit): `flutter_pos/lib/screens/pos/pos_kds_screen.dart`,
  `src/ZKTecoADMS.Api/Controllers/PosKdsController.cs`, `flutter_pos/.flutter-plugins`. **Không commit hộ.**
  Luôn `git add` đúng đường dẫn và xem `git diff --cached` trước khi commit.

## 5. Việc có thể làm tiếp (chờ người dùng quyết)
- Hạng thành viên tự áp ưu đãi: nhân điểm theo hạng, giảm giá theo hạng ở màn bán.
- Màn «Sổ đối chiếu» có nút in / xuất Excel gửi khách – NCC.
- Đồng bộ các màn khách hàng / NCC mới sang `flutter_pos` nếu bản POS cần.
