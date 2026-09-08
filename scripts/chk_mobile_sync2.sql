SELECT e."Id", e."EmployeeCode", e."ApplicationUserId", e."StoreId"
FROM "Employees" e
WHERE e."ApplicationUserId" = 'ea5931ac-bc20-4a6e-935f-bd35c0ba445e'
   OR e."Id" = 'ea5931ac-bc20-4a6e-935f-bd35c0ba445e';

SELECT du."Id", du."Pin", du."DeviceId", du."EmployeeId"
FROM "DeviceUsers" du
WHERE du."EmployeeId" IN (
  SELECT e."Id" FROM "Employees" e
  WHERE e."ApplicationUserId" = 'ea5931ac-bc20-4a6e-935f-bd35c0ba445e'
);

SELECT COUNT(*) FROM "AttendanceLogs" WHERE "MobileAttendanceRecordId" = '024a4575-864e-4f69-8d4f-32b4f243e182';

SELECT a."Id", a."PIN", a."DeviceId", a."EmployeeId", a."AttendanceTime"
FROM "AttendanceLogs" a
WHERE a."PIN" LIKE 'ea5931ac%' OR a."DeviceId" = '52cb153e-1e46-4bca-85d5-efd1b139376c'
ORDER BY a."AttendanceTime" DESC LIMIT 5;
