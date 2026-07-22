-- Fix: nhân viên cấu hình "Nghỉ N ngày bất kỳ/tháng" (PaidLeaveType off-1..off-4)
-- nhưng WeeklyOffDays vẫn mang giá trị mặc định cũ (thường là 'Sunday'), khiến
-- hệ thống tự tính "Tăng ca ngày nghỉ" mỗi khi họ đi làm Chủ nhật — sai vì
-- ngày nghỉ của họ là linh hoạt, không cố định thứ nào trong tuần.
-- Xem thêm: flutter_client/lib/screens/salary_settings_screen.dart (đã sửa
-- logic lưu để không còn xảy ra lỗi này với hồ sơ mới).

\echo 'Số hồ sơ bị ảnh hưởng (trước khi sửa):'
SELECT "Id", "PaidLeaveType", "WeeklyOffDays"
FROM "SalaryProfiles"
WHERE "PaidLeaveType" IN ('off-1', 'off-2', 'off-3', 'off-4')
  AND ("WeeklyOffDays" IS NULL OR "WeeklyOffDays" <> '');

UPDATE "SalaryProfiles"
SET "WeeklyOffDays" = ''
WHERE "PaidLeaveType" IN ('off-1', 'off-2', 'off-3', 'off-4')
  AND ("WeeklyOffDays" IS NULL OR "WeeklyOffDays" <> '');

\echo 'Số hồ sơ còn lại bị ảnh hưởng (phải là 0):'
SELECT COUNT(*)
FROM "SalaryProfiles"
WHERE "PaidLeaveType" IN ('off-1', 'off-2', 'off-3', 'off-4')
  AND ("WeeklyOffDays" IS NULL OR "WeeklyOffDays" <> '');
