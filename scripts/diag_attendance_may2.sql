SELECT s."Name", d."StoreId", COUNT(*) AS cnt
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE a."AttendanceTime" >= '2026-05-01' AND a."AttendanceTime" < '2026-06-01'
GROUP BY s."Name", d."StoreId"
ORDER BY cnt DESC
LIMIT 5;

SELECT COUNT(*) FROM "Devices" WHERE "Deleted" IS NULL;
