-- Diagnose May 2026 attendance distribution (VN store-wide sample)
SELECT 'may_total' AS metric, COUNT(*)::text AS value
FROM "AttendanceLogs"
WHERE "AttendanceTime" >= '2026-05-01' AND "AttendanceTime" < '2026-06-01';

SELECT DATE("AttendanceTime" AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Ho_Chi_Minh') AS day_vn, COUNT(*) AS cnt
FROM "AttendanceLogs"
WHERE "AttendanceTime" >= '2026-05-01' AND "AttendanceTime" < '2026-06-01'
GROUP BY 1
ORDER BY 1;

SELECT 'may_after_20' AS metric, COUNT(*)::text AS value
FROM "AttendanceLogs"
WHERE "AttendanceTime" >= '2026-05-21' AND "AttendanceTime" < '2026-06-01';

SELECT 'may_page1_sim' AS metric, COUNT(*)::text AS value
FROM (
  SELECT "Id" FROM "AttendanceLogs"
  WHERE "AttendanceTime" >= '2026-05-01' AND "AttendanceTime" < '2026-06-01'
  ORDER BY "AttendanceTime" ASC, "Id" ASC
  LIMIT 1000
) t;

SELECT MIN("AttendanceTime") AS min_t, MAX("AttendanceTime") AS max_t
FROM (
  SELECT "AttendanceTime" FROM "AttendanceLogs"
  WHERE "AttendanceTime" >= '2026-05-01' AND "AttendanceTime" < '2026-06-01'
  ORDER BY "AttendanceTime" ASC, "Id" ASC
  LIMIT 1000
) t;
