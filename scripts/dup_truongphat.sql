SELECT date_trunc('second', a."AttendanceTime") AS t,
       e."EmployeeCode", e."FirstName", e."LastName",
       COUNT(*) AS cnt,
       COUNT(DISTINCT a."Id") AS ids,
       COUNT(DISTINCT a."DeviceId") AS devs,
       MIN(a."VerifyMode") AS vmin, MAX(a."VerifyMode") AS vmax
FROM "AttendanceLogs" a
JOIN "Employees" e ON e."Id" = a."EmployeeId"
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND a."AttendanceTime" >= '2026-05-27 15:40:00'
  AND a."AttendanceTime" < '2026-05-27 15:45:00'
GROUP BY 1,2,3,4
ORDER BY cnt DESC;

SELECT a."AttendanceTime", a."VerifyMode", a."AttendanceState", a."PIN",
       d."DeviceName", a."CreatedAt"
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
LEFT JOIN "Employees" e ON e."Id" = a."EmployeeId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND a."AttendanceTime" >= '2026-05-27 15:42:00'
  AND a."AttendanceTime" < '2026-05-27 15:43:00'
ORDER BY a."AttendanceTime", a."CreatedAt";
