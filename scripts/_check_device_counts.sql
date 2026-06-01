SELECT d."DeviceName", di."AttendanceCount" AS machine_cnt,
       (SELECT COUNT(*)::int FROM "AttendanceLogs" a WHERE a."DeviceId" = d."Id") AS server_cnt
FROM "Devices" d
LEFT JOIN "DeviceInfos" di ON di."DeviceId" = d."Id"
WHERE d."Id" = '54931289-c9d5-49cb-b615-0c03726c473a';
