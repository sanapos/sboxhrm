-- Dup by employee + second
SELECT e."EmployeeCode", e."FirstName", e."LastName",
       date_trunc('second', a."AttendanceTime") AS t_sec,
       COUNT(*) AS cnt,
       COUNT(DISTINCT a."DeviceId") AS device_count,
       COUNT(DISTINCT a."PIN") AS pin_count,
       array_agg(a."VerifyMode" ORDER BY a."CreatedAt") AS modes
FROM "AttendanceLogs" a
JOIN "Employees" e ON e."Id" = a."EmployeeId"
WHERE a."AttendanceTime" >= '2026-05-27' AND a."AttendanceTime" < '2026-05-28'
GROUP BY e."EmployeeCode", e."FirstName", e."LastName", t_sec
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 25;

SELECT COUNT(*) FROM "AttendanceLogs";

-- Trường Phát store devices
SELECT s."Name", COUNT(a."Id") AS logs
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE a."AttendanceTime" >= '2026-05-27' AND a."AttendanceTime" < '2026-05-28'
GROUP BY s."Name"
ORDER BY logs DESC;
