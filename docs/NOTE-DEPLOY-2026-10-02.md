# GHI CHÚ CHO PHIÊN ĐANG LÀM PHÉP NĂM / THANH TOÁN LƯƠNG — đọc trước khi deploy (02/10/2026)

Người dùng đã duyệt: **phiên của bạn deploy luôn bản sửa này** ở lần deploy API + web tới.

## Bản sửa cần đi kèm (đã có sẵn trong thư mục làm việc của bạn)
**Thiết lập Sbox trống ở gói «Doanh nghiệp HRM»** (cửa hàng `demo`, server 103.133.224.176): gói không có Bán hàng nên
middleware chặn `/api/pos/sell-settings`, `/api/pos/commercial-profile`, `/api/pos/payment-gateway/*`,
`/api/pos/sales/bank-accounts` → mục «Thông tin cửa hàng», «Tài khoản nhận tiền» không hiện dữ liệu.

- Server: `src/ZKTecoADMS.Api/Middlewares/StorePackageModuleMiddleware.cs` — `PackageOpensSettings(...)` + 2 nhánh
  trong `IsImplicitlyAllowed`. **Đã commit** ở `4d918101` (file trong thư mục làm việc = bản đó + 6 dòng route của bạn).
- App (chưa commit, nằm trong thay đổi của bạn): `flutter_client/lib/utils/settings_hub_catalog.dart`
  (`packageModule: 'PosSell'` cho «Ngành hàng & bán hàng», «Bàn / phòng») + `settings_hub_screen.dart` (`_filterItems` kiểm `item.packageModule`).
  Giữ 2 chỗ này khi bạn sửa tiếp 2 file đó.

## Chuyện đã xảy ra trên production (đã khôi phục)
- 02/10 ~21:00: phiên khác deploy API từ worktree sạch (chỉ code đã commit) → **mất tính năng Phép năm** bạn đã deploy lúc 06:30
  từ code chưa commit. Đã **quay lại đúng image của bạn** trên cả 2 server (`zktecoadms-api:latest` = image cũ, API phép năm chạy lại).
- Bản build có sửa (không có phép năm) giữ tag `zktecoadms-api:hub-fix-20261002` — **không dùng**, chỉ để tham khảo.
- Tag dự phòng hiện có: `rollback-20261002-2051` (= image phép năm của bạn).

## Khuyến nghị
- Commit thay đổi trước khi deploy; chỉ một phiên deploy production. Deploy từ thư mục khác sẽ xóa tính năng chưa commit.
- Sau deploy kiểm: đăng nhập `demo` (Admin) → Thiết lập Sbox → «Thông tin cửa hàng», «Tài khoản nhận tiền» có dữ liệu;
  log không còn `Package block: store 985262f9… sell-settings / commercial-profile / payment-gateway`.
