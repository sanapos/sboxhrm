SELECT a."AttendanceTime", a."VerifyMode", d."DeviceName", a."Id", a."CreatedAt"
FROM "AttendanceLogs" a
LEFT JOIN "Employees" e ON e."Id" = a."EmployeeId"
LEFT JOIN "Devices" d ON d."Id" = a."DeviceId"
WHERE (e."EmployeeCode" = '36' OR a."PIN" = '36')
  AND a."AttendanceTime" >= '2026-05-27' AND a."AttendanceTime" < '2026-05-28'
ORDER BY a."AttendanceTime", a."CreatedAt";

SELECT COUNT(*) AS total_emp36
FROM "AttendanceLogs" a
LEFT JOIN "Employees" e ON e."Id" = a."EmployeeId"
WHERE (e."EmployeeCode" = '36' OR a."PIN" = '36');
