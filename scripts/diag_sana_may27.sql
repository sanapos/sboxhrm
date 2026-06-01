-- SANA: dữ liệu 27/05 (VN) và lịch sử gần đây
\set dev '290dd675-621f-478d-97f8-fa9484aae633'

SELECT COUNT(*) AS total_now FROM "AttendanceLogs" WHERE "DeviceId" = :'dev';

SELECT COUNT(*) AS on_may27
FROM "AttendanceLogs"
WHERE "DeviceId" = :'dev'
  AND "AttendanceTime" >= TIMESTAMP '2026-05-27 00:00:00'
  AND "AttendanceTime" < TIMESTAMP '2026-05-28 00:00:00';

SELECT COUNT(*) AS after_16h_may27
FROM "AttendanceLogs"
WHERE "DeviceId" = :'dev'
  AND "AttendanceTime" >= TIMESTAMP '2026-05-27 16:00:00'
  AND "AttendanceTime" < TIMESTAMP '2026-05-28 00:00:00';

SELECT "AttendanceTime", "PIN", "CreatedAt", "VerifyMode"
FROM "AttendanceLogs"
WHERE "DeviceId" = :'dev'
ORDER BY "AttendanceTime" DESC
LIMIT 20;

-- Lệnh xóa / sync gần đây
SELECT "CommandType", "Status", "Command", "CreatedAt", "SentAt", "CompletedAt"
FROM "DeviceCommands"
WHERE "DeviceId" = :'dev'
ORDER BY "CreatedAt" DESC
LIMIT 12;
