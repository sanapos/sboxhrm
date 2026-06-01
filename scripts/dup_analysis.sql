-- Exact dup: same device + pin + time
SELECT 'exact_device_pin_time' AS kind, COUNT(*) AS dup_groups
FROM (
  SELECT "DeviceId", "PIN", "AttendanceTime", COUNT(*) c
  FROM "AttendanceLogs"
  WHERE "AttendanceTime" >= '2026-05-27' AND "AttendanceTime" < '2026-05-28'
  GROUP BY 1,2,3 HAVING COUNT(*) > 1
) t;

-- Same employee + time (any device)
SELECT e."EmployeeCode", e."FirstName", e."LastName", a."AttendanceTime", COUNT(*) AS cnt,
       array_agg(DISTINCT d."DeviceName") AS devices,
       array_agg(DISTINCT a."VerifyMode") AS verify_modes
FROM "AttendanceLogs" a
JOIN "Employees" e ON e."Id" = a."EmployeeId"
LEFT JOIN "Devices" d ON d."Id" = a."DeviceId"
WHERE a."AttendanceTime" >= '2026-05-27' AND a."AttendanceTime" < '2026-05-28'
GROUP BY e."EmployeeCode", e."FirstName", e."LastName", a."AttendanceTime"
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 20;

-- Nguyen Thi Bich Thuy / code 36 on 27/5 around 15:42
SELECT a."AttendanceTime", a."PIN", a."VerifyMode", d."DeviceName", a."Id"
FROM "AttendanceLogs" a
LEFT JOIN "Devices" d ON d."Id" = a."DeviceId"
LEFT JOIN "Employees" e ON e."Id" = a."EmployeeId"
WHERE a."AttendanceTime" >= '2026-05-27 15:40:00' AND a."AttendanceTime" < '2026-05-27 15:45:00'
  AND (e."EmployeeCode" = '36' OR e."FirstName" ILIKE '%Bich%Thuy%')
ORDER BY a."AttendanceTime", a."CreatedAt";

-- Store total + dup rate all time (sample)
SELECT COUNT(*) AS total,
       COUNT(*) - COUNT(DISTINCT ("DeviceId", "PIN", "AttendanceTime")) AS exact_dup_rows
FROM "AttendanceLogs"
WHERE "AttendanceTime" >= '2026-02-27';
