-- Simulate client stopping at 1000 oldest logs (Jun 2026, Trường Phát)
WITH store AS (
  SELECT "Id" FROM "Stores" WHERE "Code" = 'truongphat' LIMIT 1
),
ordered AS (
  SELECT a."PIN", a."AttendanceTime", a."AttendanceState",
         ROW_NUMBER() OVER (ORDER BY a."AttendanceTime" ASC, a."Id") AS rn
  FROM "AttendanceLogs" a
  JOIN "Devices" d ON d."Id" = a."DeviceId"
  WHERE d."StoreId" = (SELECT "Id" FROM store)
    AND a."AttendanceTime" >= '2026-06-01'
    AND a."AttendanceTime" < '2026-07-01'
),
first1000 AS (
  SELECT * FROM ordered WHERE rn <= 1000
)
SELECT "PIN",
       COUNT(*) AS punches_in_first1000,
       COUNT(DISTINCT DATE("AttendanceTime")) AS calendar_days,
       MAX(DATE("AttendanceTime")) AS last_day_in_subset
FROM first1000
GROUP BY "PIN"
ORDER BY calendar_days ASC
LIMIT 20;

\echo '--- cutoff day for row 1000 ---'
WITH store AS (
  SELECT "Id" FROM "Stores" WHERE "Code" = 'truongphat' LIMIT 1
),
ordered AS (
  SELECT a."AttendanceTime",
         ROW_NUMBER() OVER (ORDER BY a."AttendanceTime" ASC, a."Id") AS rn
  FROM "AttendanceLogs" a
  JOIN "Devices" d ON d."Id" = a."DeviceId"
  WHERE d."StoreId" = (SELECT "Id" FROM store)
    AND a."AttendanceTime" >= '2026-06-01'
    AND a."AttendanceTime" < '2026-07-01'
)
SELECT DATE("AttendanceTime") AS cutoff_day, COUNT(*) AS cnt
FROM ordered WHERE rn <= 1000
GROUP BY 1 ORDER BY 1 DESC LIMIT 5;

\echo '--- logical day (day_end 05:00) distinct days per PIN full month ---'
WITH store AS (
  SELECT "Id" FROM "Stores" WHERE "Code" = 'truongphat' LIMIT 1
),
logs AS (
  SELECT a."PIN", a."AttendanceTime",
    CASE WHEN (EXTRACT(HOUR FROM a."AttendanceTime") * 60 + EXTRACT(MINUTE FROM a."AttendanceTime")) < 300
         THEN DATE(a."AttendanceTime" - INTERVAL '1 day')
         ELSE DATE(a."AttendanceTime") END AS logical_day
  FROM "AttendanceLogs" a
  JOIN "Devices" d ON d."Id" = a."DeviceId"
  WHERE d."StoreId" = (SELECT "Id" FROM store)
    AND a."AttendanceTime" >= '2026-05-31'
    AND a."AttendanceTime" < '2026-07-01'
)
SELECT "PIN", COUNT(DISTINCT logical_day) AS logical_days, COUNT(*) AS punches
FROM logs
WHERE logical_day >= '2026-06-01' AND logical_day <= '2026-06-30'
GROUP BY "PIN"
ORDER BY logical_days ASC
LIMIT 15;
