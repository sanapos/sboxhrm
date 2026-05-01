SELECT MIN("AttendanceTime"), MAX("AttendanceTime"), COUNT(*) FROM "AttendanceLogs" WHERE "AttendanceTime" >= '2026-04-28' AND "AttendanceTime" < '2026-04-30';
SELECT "PIN", "AttendanceTime", "AttendanceState" FROM "AttendanceLogs" WHERE "AttendanceTime" >= '2026-04-28' AND "AttendanceTime" < '2026-04-30' ORDER BY "AttendanceTime" LIMIT 20;
