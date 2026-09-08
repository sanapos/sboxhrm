-- Trường Phát: thống kê chấm công tháng 6/2026 (tháng trước so với 4/7/2026)
\set ON_ERROR_STOP on

SELECT "Id", "Name", "Code"
FROM "Stores"
WHERE "Name" ILIKE '%Trường Phát%' OR "Code" ILIKE '%truongphat%';

\echo '--- Total logs Jun 2026 ---'
SELECT COUNT(*) AS total_logs
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE (s."Name" ILIKE '%Trường Phát%' OR s."Code" ILIKE '%truongphat%')
  AND a."AttendanceTime" >= '2026-06-01'
  AND a."AttendanceTime" < '2026-07-01';

\echo '--- Distinct PINs Jun 2026 ---'
SELECT COUNT(DISTINCT a."PIN") AS distinct_pins
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE (s."Name" ILIKE '%Trường Phát%' OR s."Code" ILIKE '%truongphat%')
  AND a."AttendanceTime" >= '2026-06-01'
  AND a."AttendanceTime" < '2026-07-01';

\echo '--- Days per PIN (top 15) ---'
SELECT a."PIN",
       COUNT(*) AS total_punches,
       COUNT(DISTINCT DATE(a."AttendanceTime")) AS distinct_calendar_days,
       MIN(DATE(a."AttendanceTime")) AS first_day,
       MAX(DATE(a."AttendanceTime")) AS last_day
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE (s."Name" ILIKE '%Trường Phát%' OR s."Code" ILIKE '%truongphat%')
  AND a."AttendanceTime" >= '2026-06-01'
  AND a."AttendanceTime" < '2026-07-01'
GROUP BY a."PIN"
ORDER BY total_punches DESC
LIMIT 15;

\echo '--- Daily store total Jun 2026 ---'
SELECT DATE(a."AttendanceTime") AS day, COUNT(*) AS punches
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE (s."Name" ILIKE '%Trường Phát%' OR s."Code" ILIKE '%truongphat%')
  AND a."AttendanceTime" >= '2026-06-01'
  AND a."AttendanceTime" < '2026-07-01'
GROUP BY 1
ORDER BY 1;

\echo '--- Devices ---'
SELECT d."Id", d."DeviceName", d."IsActive"
FROM "Devices" d
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%' OR s."Code" ILIKE '%truongphat%';

\echo '--- day_end_time setting ---'
SELECT "Key", "Value" FROM "AppSettings"
WHERE "Key" = 'day_end_time'
LIMIT 5;
