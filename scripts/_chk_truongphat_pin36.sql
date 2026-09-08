-- PIN 36 (active employee): full month vs first-1000 subset
WITH store AS (SELECT "Id" FROM "Stores" WHERE "Code"='truongphat'),
logs AS (
  SELECT a."PIN", a."AttendanceTime", a."Id",
    CASE WHEN (EXTRACT(HOUR FROM a."AttendanceTime") * 60 + EXTRACT(MINUTE FROM a."AttendanceTime")) < 300
         THEN DATE(a."AttendanceTime" - INTERVAL '1 day')
         ELSE DATE(a."AttendanceTime") END AS logical_day,
    ROW_NUMBER() OVER (ORDER BY a."AttendanceTime" ASC, a."Id") AS rn
  FROM "AttendanceLogs" a
  JOIN "Devices" d ON d."Id"=a."DeviceId"
  WHERE d."StoreId"=(SELECT "Id" FROM store)
    AND a."AttendanceTime">='2026-05-31' AND a."AttendanceTime"<'2026-07-02'
)
SELECT 'full_june' AS scope,
       COUNT(DISTINCT logical_day) FILTER (WHERE logical_day BETWEEN '2026-06-01' AND '2026-06-30') AS logical_days,
       COUNT(*) FILTER (WHERE logical_day BETWEEN '2026-06-01' AND '2026-06-30') AS punches
FROM logs WHERE "PIN"='36'
UNION ALL
SELECT 'first1000_only',
       COUNT(DISTINCT logical_day) FILTER (WHERE logical_day BETWEEN '2026-06-01' AND '2026-06-30'),
       COUNT(*) FILTER (WHERE logical_day BETWEEN '2026-06-01' AND '2026-06-30' AND rn<=1000)
FROM logs WHERE "PIN"='36';

\echo '--- avg logical days if only first 1000 logs (active PINs >=50 punches) ---'
WITH store AS (SELECT "Id" FROM "Stores" WHERE "Code"='truongphat'),
ordered AS (
  SELECT a."PIN", a."AttendanceTime", a."Id",
    CASE WHEN (EXTRACT(HOUR FROM a."AttendanceTime") * 60 + EXTRACT(MINUTE FROM a."AttendanceTime")) < 300
         THEN DATE(a."AttendanceTime" - INTERVAL '1 day')
         ELSE DATE(a."AttendanceTime") END AS logical_day,
    ROW_NUMBER() OVER (ORDER BY a."AttendanceTime" ASC, a."Id") AS rn
  FROM "AttendanceLogs" a JOIN "Devices" d ON d."Id"=a."DeviceId"
  WHERE d."StoreId"=(SELECT "Id" FROM store)
    AND a."AttendanceTime">='2026-05-31' AND a."AttendanceTime"<'2026-07-02'
),
full_m AS (
  SELECT "PIN", COUNT(DISTINCT logical_day) FILTER (WHERE logical_day BETWEEN '2026-06-01' AND '2026-06-30') AS days_full
  FROM ordered GROUP BY "PIN" HAVING COUNT(*) FILTER (WHERE logical_day BETWEEN '2026-06-01' AND '2026-06-30') >= 50
),
sub_m AS (
  SELECT "PIN", COUNT(DISTINCT logical_day) FILTER (WHERE logical_day BETWEEN '2026-06-01' AND '2026-06-30' AND rn<=1000) AS days_sub
  FROM ordered GROUP BY "PIN" HAVING COUNT(*) FILTER (WHERE logical_day BETWEEN '2026-06-01' AND '2026-06-30') >= 50
)
SELECT ROUND(AVG(f.days_full),1) AS avg_days_full_june,
       ROUND(AVG(s.days_sub),1) AS avg_days_if_stop_at_1000
FROM full_m f JOIN sub_m s USING("PIN");
