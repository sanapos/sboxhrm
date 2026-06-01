SELECT 'VERIFY' AS phase, COUNT(*) AS server_total
FROM "AttendanceLogs" WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633';

SELECT "Id", "AttendanceTime", "PIN", "CreatedAt"
FROM "AttendanceLogs"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
  AND "AttendanceTime" >= '2026-05-27' AND "AttendanceTime" < '2026-05-28';

SELECT "Status", "Command", "SentAt", "CreatedAt"
FROM "DeviceCommands"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633' AND "CommandType" = 7
ORDER BY "CreatedAt" DESC LIMIT 3;
