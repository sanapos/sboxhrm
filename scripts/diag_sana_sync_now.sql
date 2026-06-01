SELECT "Status", COUNT(*) FROM "DeviceCommands"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633' AND "CommandType" = 7
GROUP BY "Status";

SELECT "Status", "SentAt", "CreatedAt", LEFT("Command", 60) AS cmd
FROM "DeviceCommands"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633' AND "CommandType" = 7
ORDER BY "CreatedAt" DESC LIMIT 5;

SELECT COUNT(*) AS server_count FROM "AttendanceLogs"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633';

SELECT "AttendanceCount" FROM "DeviceInfos"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633';
