SELECT "AttendanceTime", "CreatedAt"
FROM "AttendanceLogs"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
ORDER BY "AttendanceTime" DESC
LIMIT 10;
