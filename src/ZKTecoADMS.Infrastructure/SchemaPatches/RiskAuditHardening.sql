-- Không lưu mật khẩu plain text nữa: xoá giá trị cũ (giữ cột để không vỡ schema / bản cũ đang chạy)
UPDATE "AspNetUsers" SET "PlainTextPassword" = NULL WHERE "PlainTextPassword" IS NOT NULL;

-- Máy chấm công hỏi lệnh chờ mỗi vài giây (DeviceId + Status) → trước đây quét cả bảng hàng triệu lần
CREATE INDEX IF NOT EXISTS "IX_DeviceCommands_Device_Status" ON "DeviceCommands" ("DeviceId", "Status");
-- Báo cáo chấm công theo khoảng ngày của cả cửa hàng (nhiều máy) — không có index chỉ theo thời gian
CREATE INDEX IF NOT EXISTS "IX_AttendanceLogs_AttendanceTime" ON "AttendanceLogs" ("AttendanceTime");
