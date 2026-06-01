-- SANA device deep diagnostic (run on production)
\set sana_id '290dd675-621f-478d-97f8-fa9484aae633'

SELECT d."Id", d."DeviceName", d."SerialNumber", d."StoreId", d."LastOnline", d."DeviceStatus"
FROM "Devices" d
WHERE d."Id" = :'sana_id' OR d."DeviceName" ILIKE '%SANA%';

SELECT COUNT(*) AS total_all_time
FROM "AttendanceLogs"
WHERE "DeviceId" = :'sana_id';

SELECT COUNT(*) AS today_vn
FROM "AttendanceLogs"
WHERE "DeviceId" = :'sana_id'
  AND "AttendanceTime" >= (CURRENT_DATE AT TIME ZONE 'Asia/Ho_Chi_Minh')
  AND "AttendanceTime" < ((CURRENT_DATE + 1) AT TIME ZONE 'Asia/Ho_Chi_Minh');

SELECT COUNT(*) AS last_24h
FROM "AttendanceLogs"
WHERE "DeviceId" = :'sana_id'
  AND "AttendanceTime" >= NOW() - interval '24 hours';

SELECT "AttendanceTime", "PIN", "VerifyMode", "CreatedAt"
FROM "AttendanceLogs"
WHERE "DeviceId" = :'sana_id'
ORDER BY "AttendanceTime" DESC
LIMIT 15;

SELECT dc."Status", dc."CommandType", dc."SentAt", dc."CreatedAt", dc."Command"
FROM "DeviceCommands" dc
WHERE dc."DeviceId" = :'sana_id'
  AND dc."CommandType" = 7
ORDER BY dc."CreatedAt" DESC
LIMIT 8;

-- Any store device with punches today?
SELECT d."DeviceName", COUNT(*) AS today_cnt
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
WHERE a."AttendanceTime" >= (CURRENT_DATE AT TIME ZONE 'Asia/Ho_Chi_Minh')
  AND a."AttendanceTime" < ((CURRENT_DATE + 1) AT TIME ZONE 'Asia/Ho_Chi_Minh')
GROUP BY d."DeviceName"
ORDER BY today_cnt DESC
LIMIT 10;
