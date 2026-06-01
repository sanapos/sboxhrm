-- Many rows sharing exact CreatedAt (bulk insert) -> unstable pagination
SELECT "CreatedAt", COUNT(*) AS cnt
FROM "AttendanceLogs"
GROUP BY "CreatedAt"
HAVING COUNT(*) > 3
ORDER BY cnt DESC
LIMIT 15;

-- Same second CreatedAt for Trường Phát May 27
SELECT date_trunc('second', "CreatedAt") AS created_sec, COUNT(*) AS cnt
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND a."AttendanceTime" >= '2026-05-27'
GROUP BY 1
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 10;

-- VerifyMode distribution store Trường Phát
SELECT "VerifyMode", COUNT(*)
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
GROUP BY 1;
