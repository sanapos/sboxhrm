SELECT date_trunc('second', "AttendanceTime") AS t, COUNT(*) AS cnt
FROM "AttendanceLogs" a
LEFT JOIN "Employees" e ON e."Id" = a."EmployeeId"
WHERE (e."EmployeeCode" = '36' OR a."PIN" = '36')
GROUP BY 1
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 20;

SELECT COUNT(*) AS in_range
FROM "AttendanceLogs" a
JOIN "Devices" d ON d."Id" = a."DeviceId"
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND a."AttendanceTime" >= '2026-02-27' AND a."AttendanceTime" < '2026-05-29';
