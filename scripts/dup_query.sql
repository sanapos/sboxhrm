SELECT "PIN", "AttendanceTime", COUNT(*) AS cnt, MIN("DeviceId"::text) AS dev
FROM "AttendanceLogs"
WHERE "AttendanceTime" >= '2026-05-27' AND "AttendanceTime" < '2026-05-28'
GROUP BY "PIN", "AttendanceTime"
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 15;
