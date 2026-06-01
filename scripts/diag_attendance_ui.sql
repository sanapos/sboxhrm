-- Chẩn đoán: dữ liệu chấm công vs lệnh sync
SELECT NOW() AT TIME ZONE 'Asia/Ho_Chi_Minh' AS vn_now;

SELECT d."DeviceName", d."Id", d."StoreId", COUNT(a."Id") AS att_total
FROM "Devices" d
LEFT JOIN "AttendanceLogs" a ON a."DeviceId" = d."Id"
GROUP BY d."DeviceName", d."Id", d."StoreId"
ORDER BY att_total DESC
LIMIT 10;

SELECT COUNT(*) AS att_90d
FROM "AttendanceLogs"
WHERE "AttendanceTime" >= NOW() - interval '90 days';

SELECT MAX("AttendanceTime") AS latest_att, MIN("AttendanceTime") AS oldest_90d
FROM "AttendanceLogs"
WHERE "AttendanceTime" >= NOW() - interval '90 days';

SELECT dc."Status", dc."CommandType", d."DeviceName", dc."CreatedAt", dc."SentAt", LEFT(dc."Command", 80) AS cmd
FROM "DeviceCommands" dc
JOIN "Devices" d ON d."Id" = dc."DeviceId"
WHERE dc."CommandType" = 7
ORDER BY dc."CreatedAt" DESC
LIMIT 8;
