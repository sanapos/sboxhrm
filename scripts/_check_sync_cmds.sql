SELECT "Status", COUNT(*) FROM "DeviceCommands"
WHERE "DeviceId" = '54931289-c9d5-49cb-b615-0c03726c473a' AND "CommandType" = 7
GROUP BY "Status";

SELECT MAX("CreatedAt") AS last_attlog FROM "AttendanceLogs"
WHERE "DeviceId" = '54931289-c9d5-49cb-b615-0c03726c473a';
