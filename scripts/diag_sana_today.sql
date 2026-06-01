SELECT COUNT(*) AS sana_today
FROM "AttendanceLogs"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
  AND "AttendanceTime" >= '2026-05-27'
  AND "AttendanceTime" < '2026-05-28';

SELECT "AttendanceTime", "PIN"
FROM "AttendanceLogs"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
ORDER BY "AttendanceTime" DESC
LIMIT 5;
