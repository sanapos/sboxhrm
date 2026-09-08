-- Unstable pagination: same AttendanceTime second
SELECT date_trunc('second', a."AttendanceTime") AS t, COUNT(*) AS cnt
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE s."Code" = 'truongphat'
  AND a."AttendanceTime" >= '2026-06-01'
  AND a."AttendanceTime" < '2026-07-01'
GROUP BY 1
HAVING COUNT(*) > 3
ORDER BY cnt DESC
LIMIT 15;

\echo '--- overlap page1/page2 ids if sort only by time (simulate) ---'
WITH store AS (SELECT "Id" FROM "Stores" WHERE "Code"='truongphat'),
logs AS (
  SELECT a."Id", a."AttendanceTime"
  FROM "AttendanceLogs" a
  JOIN "Devices" d ON d."Id"=a."DeviceId"
  WHERE d."StoreId"=(SELECT "Id" FROM store)
    AND a."AttendanceTime">='2026-05-31' AND a."AttendanceTime"<'2026-07-02'
),
p1 AS (SELECT "Id" FROM logs ORDER BY "AttendanceTime" ASC OFFSET 0 LIMIT 1000),
p2 AS (SELECT "Id" FROM logs ORDER BY "AttendanceTime" ASC OFFSET 1000 LIMIT 1000)
SELECT
  (SELECT COUNT(*) FROM p1) AS page1,
  (SELECT COUNT(*) FROM p2) AS page2,
  (SELECT COUNT(*) FROM p1 JOIN p2 USING("Id")) AS overlap;
