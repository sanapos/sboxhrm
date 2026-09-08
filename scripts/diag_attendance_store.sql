SELECT "StoreCode", "Name" FROM "Stores" WHERE "Id" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad';

SELECT COUNT(*) AS store_may_total
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
WHERE d."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND a."AttendanceTime" >= '2026-05-01' AND a."AttendanceTime" < '2026-06-01';

SELECT MAX(sub."AttendanceTime") AS page1_max_time
FROM (
  SELECT a."AttendanceTime"
  FROM "AttendanceLogs" a
  JOIN "Devices" d ON d."Id" = a."DeviceId"
  WHERE d."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
    AND a."AttendanceTime" >= '2026-05-01' AND a."AttendanceTime" < '2026-06-01'
  ORDER BY a."AttendanceTime" ASC
  LIMIT 1000
) sub;

SELECT MIN(sub."AttendanceTime") AS page2_min_time
FROM (
  SELECT a."AttendanceTime"
  FROM "AttendanceLogs" a
  JOIN "Devices" d ON d."Id" = a."DeviceId"
  WHERE d."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
    AND a."AttendanceTime" >= '2026-05-01' AND a."AttendanceTime" < '2026-06-01'
  ORDER BY a."AttendanceTime" ASC
  OFFSET 1000 LIMIT 10
) sub;
