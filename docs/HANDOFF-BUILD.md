# Bàn giao build — nhánh `fix/tingee-agent-scope-deploy`

Tài liệu cho người / Claude tiếp nhận build & triển khai. Cập nhật: 28/09/2026.

## Trạng thái khi bàn giao
| Hạng mục | Kết quả |
|---|---|
| `dotnet build src/ZKTecoADMS.Api` | Thành công (chỉ cảnh báo cũ) |
| `dotnet test src/ZKTecoADMS.Tests` | 244/244 đạt |
| `flutter analyze --no-pub` (flutter_client, flutter_pos) | 0 lỗi (còn info/warning cũ) |
| Chạy thử trên thiết bị thật | **Chưa** |
| Deploy server / build APK / web | **Chưa** |

Flutter SDK trên máy dev: `C:\FlutterSDK\bin\flutter.bat`.

## Lệnh kiểm tra nhanh
```bash
dotnet build src/ZKTecoADMS.Api/ZKTecoADMS.Api.csproj
dotnet test src/ZKTecoADMS.Tests/ZKTecoADMS.Tests.csproj
cd flutter_client && flutter analyze --no-pub
cd flutter_pos && flutter analyze --no-pub
```
Script deploy có sẵn ở `tools/deploy_api.sh`, `tools/deploy_web.sh` — đọc kỹ trước khi chạy (đẩy lên server thật).

## Cơ sở dữ liệu
Không có EF migration mới. Bảng / cột mới được tạo tự động khi API khởi động qua
`ZKTecoDbInitializer` (`CREATE TABLE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS`) — an toàn chạy lại nhiều lần.
Bảng mới: `EmployeeLocationPoints`, `UserNotificationSettings`, `StoreNotificationTemplates`; thêm cột cho
`MealRecords` (TicketNo, Price, Source, PrintedAt, PrintCount), `Feedbacks` (Code, Topic, Priority, DueAt, …), `FeedbackReplies.Kind`.
→ Nên sao lưu DB trước khi deploy API.

## Các thay đổi chính (tóm tắt)
- **Suất ăn / căn tin**: menu hôm nay, phiếu ăn in khi chấm tại máy căn tin, tổng hợp số suất, công nợ tiền ăn
  (`MealCanteenController`, `MealRules`, `screens/meal/*`).
- **Kiến nghị / khiếu nại**: viết lại (mã phiếu, ưu tiên, hạn xử lý, người phụ trách, ẩn danh, đánh giá, mở lại)
  (`FeedbackController`, `FeedbackRules`, `screens/feedback/*`).
- **Bản đồ nhân sự**: vị trí trực tiếp + lộ trình trong ca (`StaffMapController`, `RouteAnalyzer`, `screens/staff_map/*`).
  Đã xoá `field_checkin_screen.dart`.
- **Lịch làm việc (Shift hub)**: ca, duyệt ca, xin nghỉ, đổi ca, định mức (`ShiftHubController`, `ShiftCoverageRules`, `screens/shift_hub/*`).
- **Tổng hợp công / lương**: sửa logic thuế TNCN, NV nghỉ việc, ngày vắng; sửa / thêm giờ nhanh trên bảng có giờ gợi ý theo ca
  (`attendance_summary_tab`, `attendance_by_shift_tab`, `payroll_summary_tab`, `widgets/attendance/*`, `AttendanceEditMarksController`).
- **Đăng nhập / đăng ký**: thông báo lỗi chung, kiểm tra mã cửa hàng / email trực tiếp, gợi ý mã, độ mạnh mật khẩu,
  rate-limit `auth-lookup` (`AuthController`, `StoreCodeRules`, `widgets/auth/*`).
- **Thông báo / FCM**: lọc theo loại phía server, bỏ đọc, đọc theo nhóm, giờ yên lặng, gửi thử, mẫu thông báo cửa hàng,
  màn soạn gửi cho nhân viên; sửa lỗi gửi hàng loạt bỏ qua gói FCM, lỗi thông báo cùng loại đè nhau trên Android
  (`NotificationCenterController`, `PushNotificationService`, `NotificationQuietRules`, `screens/notifications/*`).
- Ngoài ra nhánh còn các thay đổi trước đó chưa commit: Truyền thông nội bộ v2, Công việc v2, Tài chính nhân sự,
  Hoá đơn điện tử (MISA / VNPT), Tổng quan kinh doanh, KPI / sản xuất, Duyệt chấm công v2, tài sản.

## Lưu ý khi build app di động
- Android: app tạo 2 kênh thông báo mới `attendance_urgent`, `attendance_quiet` (trong `fcm_service.dart`).
  Server đã gửi theo kênh này → cần phát hành bản app mới để giờ yên lặng có hiệu lực trên Android.
- `flutter_pos` dùng chung một số file với `flutter_client` (e-invoice, print template) — build cả hai.

## Nên kiểm thử sau khi deploy
1. Chấm công tại máy căn tin → in phiếu ăn; báo cáo suất ăn + công nợ.
2. Gửi 2 thông báo chấm công liên tiếp → Android hiện đủ 2 (không đè).
3. Cài đặt thông báo → bật giờ yên lặng → "Gửi thử cho tôi".
4. Quản lý: Thông báo → "Gửi thông báo cho nhân viên" với biến `{ten}` cho 1 phòng ban.
5. Đăng nhập sai mật khẩu / mã cửa hàng; đăng ký cửa hàng mới với mã trùng → có gợi ý mã.
6. Bảng lương: NV nghỉ việc giữa tháng, thuế TNCN có hoa hồng / KPI.

## Bổ sung: deploy + build iOS (phiên Tài chính NS / Duyệt chấm công v2, 28/09/2026)
Mã của phiên này đã nằm trong commit `e800cff`. Phần bổ sung tài liệu này chưa commit — commit kèm khi bắt đầu.

1. `git push origin fix/tingee-agent-scope-deploy` (nhánh đi trước GitHub 1 commit).
2. Chạy lại `dotnet test` + `flutter test` (flutter_client). Test "App loads successfully" trong `widget_test.dart` lỗi sẵn — bỏ qua.
3. Tag dự phòng trên 2 server trước khi deploy — chỉ dùng SSH key, **không** dùng mật khẩu người dùng từng gửi:
   `ssh -i "$USERPROFILE/.ssh/sbox_deploy_ed25519" -o BatchMode=yes root@103.133.225.67 "docker tag zktecoadms-api:latest zktecoadms-api:rollback-YYYYMMDD-HHMM"` (tương tự 103.133.224.176)
4. Deploy API (PowerShell): `$env:SBOX_DEPLOY_KEY="$env:USERPROFILE\.ssh\sbox_deploy_ed25519"; foreach ($ip in "103.133.225.67","103.133.224.176") { .\scripts\deploy-api-only.ps1 -Server $ip }`
5. Deploy web: `$env:Path="C:\Users\TH DECOR\flutter\bin;$env:Path"; .\scripts\deploy-flutter-web-only.ps1 -Target both`
6. Build iOS + Android qua Codemagic từ nhánh đã push — không in/copy token Codemagic. Không sửa code khi đang đóng gói.
7. Nhắc người dùng: dán lại URL webhook vận chuyển ở các hãng; build lại APK POS.

**App cũ với server mới:** không lỗi (trường mới tùy chọn, enum mới bị kẹp → chỉ sai nhãn). Rủi ro duy nhất: bật «Bắt buộc lý do chấm ngoài vị trí» cho NV dùng app cũ → NV đó không chấm ngoài vị trí được (mặc định tắt; bật sau khi NV cập nhật app). Hành vi mới áp dụng cả app cũ: tự duyệt bản chấm «tin cậy» (mặc định bật), hạn mức ứng 50% lương/kỳ, duyệt phiếu phạt mặc định trừ lương.

**Kiểm thử thêm:** thưởng tiền mặt → có phiếu chi, bảng lương không cộng; xin ứng vượt hạn mức → báo lỗi; chấm ngoài vị trí gần (<300 m, mặt ≥85%) → tự duyệt, xa → hộp duyệt có bản đồ; «Duyệt + phạt» bổ sung công → có phiếu phạt quên chấm.

**Ràng buộc:** tiếng Việt; không in API key; DB production chỉ kiểm tra schema/đếm; commit kết thúc bằng `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Bổ sung: chi nhánh đầy đủ + báo cáo hiện đại (28/09/2026)
- **Tồn kho theo chi nhánh**: `PosBranchStocks` (chi nhánh ngoài trụ sở), trụ sở = tổng − các CN khác − hàng đang chuyển.
  `BranchStockInterceptor` tự ghi chênh lệch tồn vào chi nhánh của thao tác. Chuyển kho: `PosStockTransfers` / `Lines`, API `api/branch-ops`.
- **Ngữ cảnh chi nhánh**: `BranchContextMiddleware` (header `X-Branch-Id`, `?branchId=`, danh sách CN được phép). App: `BranchSession`, `BranchSwitcher`.
- **Báo cáo chi nhánh / Kho chi nhánh / Chuyển kho / Chi tiết chi nhánh**: `flutter_client/lib/screens/branch_ops/*`.
- Cột `BranchId` mới trên 8 bảng chứng từ; khi API khởi động, dữ liệu cũ (null) được gán về trụ sở.

**App cũ với server mới:** không lỗi — app cũ không gửi `X-Branch-Id` → server dùng chi nhánh của NV, không có thì trụ sở.
Thay đổi hành vi (chỉ cửa hàng có ≥ 2 chi nhánh): NV / quản lý không phải Admin/Giám đốc/Kế toán, đã gán vào chi nhánh
khác trụ sở, chỉ thấy đơn POS / thu chi của chi nhánh mình (lịch sử cũ nằm ở trụ sở). Khi kiểm tra DB 28/09: server
103.133.224.176 có 5 cửa hàng ≥ 2 CN, ~10 tài khoản bị ảnh hưởng, 0 sản phẩm POS; server 103.133.225.67 không có.
Giới hạn: bán hàng vẫn kiểm tồn theo tổng (tồn CN có thể âm); giao diện chuyển kho theo mặt hàng (chưa tách biến thể).

## Bổ sung: nâng cấp phân quyền (29/09/2026)
- **Quyền Xuất** áp cho báo giá (Excel/Word/PDF/gửi file), lịch sử thao tác, công việc, máy in, vận chuyển + nút xuất ~35 màn app
  (`utils/export_permission_guard.dart`, `PosReportMobileScaffold.exportModule`). Một lần duy nhất (`SboxDataMigrations` id
  `perm-export-v1`): ai đang Xem các chức năng này được bật Xuất.
- **Quyền con bán hàng**: `PosSellPriceEdit` (Sửa giá), `PosSellDiscount` (Giảm giá), `PosSellCancelPaid` (Hủy HĐ đã thu),
  `PosViewCost` (Xem giá vốn). `PatchPermissionSplitAsync` chèn dòng còn thiếu sao chép từ quyền cha (không ghi đè chỉnh tay).
  Giá / chiết khấu đã có trên đơn tạm giữ nguyên thì không cần quyền (`PriorPricing`).
- **Giá vốn**: `[MaskCostData]` bỏ trường giá vốn / giá trị tồn / lãi khỏi JSON khi thiếu PosViewCost; sửa hàng / biến thể / import
  giữ nguyên giá vốn cũ; xuất Excel hàng hóa để trống cột giá vốn.
- **Chi nhánh**: `BranchStockInterceptor.GuardBranchWritesAsync` — người bị giới hạn chi nhánh chỉ ghi đơn / phiếu kho / thu chi
  trong chi nhánh được phép + theo cờ Thêm/Sửa/Xóa của phân quyền chi nhánh → `ForbiddenException` (403).
- **Vai trò → quyền**: Thu chi, TK ngân hàng, phụ cấp, bậc lương ca bỏ điều kiện «từ Quản lý» (chỉ cần quyền chức năng — Kế toán
  dùng được như đã tick); Phiếu lương / thưởng phạt / giao dịch lương dùng policy `ManagerOrAccountant` (NV có Xem phiếu lương
  của mình nên không mở cho mọi vai trò).
- **Bảo mật**: `POST api/sampledata/seed/{code}` ẩn danh chỉ trong 30 phút đầu sau khi tạo cửa hàng (trước đây ai biết mã cửa hàng
  chưa có NV đều tạo được tài khoản Quản lý mật khẩu cố định).

## Bổ sung: mẫu phân quyền HRM / POS / HRM + POS (29/09/2026)
- `Application/Authorization/PermissionPresetCatalog.cs`: 20 mẫu gắn với vai trò hệ thống (tài khoản chỉ gán được vai trò có sẵn).
  HRM: Giám đốc, Quản lý nhân sự, Trưởng phòng, Kế toán lương, Nhân viên. POS: Chủ cửa hàng, Quản lý cửa hàng, Kế toán bán hàng,
  Thủ kho (vai trò Trưởng phòng), Thu ngân, Phục vụ, Nhân viên kinh doanh (vai trò Nhân viên). HRM + POS: gộp tương ứng.
  Gói nhận diện từ chức năng được phép của cửa hàng; chức năng ngoài gói không được cấp.
- API `GET api/permissions/presets[?package=hrm|pos|full]`, `GET api/permissions/presets/{id}`, `POST api/permissions/presets/apply`.
- Tạo cửa hàng mới + nút «Khôi phục mặc định» dùng mẫu theo gói. App: nút «Mẫu phân quyền» / «Nạp mẫu» trên màn Phân quyền.
- Vá: `api/permissions/*` chỉ SuperAdmin chọn được cửa hàng khác; lưu / khôi phục quyền không còn đụng dòng quyền dùng chung
  (StoreId null — production hiện có 0 dòng); dòng riêng cửa hàng được ưu tiên hơn dòng dùng chung.

## Không nằm trong commit
Các thư mục / file tạm và bản build trong gốc repo (`.tmp-*`, `dist/`, `installed*_apk/`, ảnh chụp, log build)
và các dự án riêng chưa từng được theo dõi: `android_pos/`, `tools/SboxPrintAgent/`, `firmware/`.
