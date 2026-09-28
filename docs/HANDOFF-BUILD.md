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

## Không nằm trong commit
Các thư mục / file tạm và bản build trong gốc repo (`.tmp-*`, `dist/`, `installed*_apk/`, ảnh chụp, log build)
và các dự án riêng chưa từng được theo dõi: `android_pos/`, `tools/SboxPrintAgent/`, `firmware/`.
