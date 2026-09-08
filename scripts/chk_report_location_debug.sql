-- Debug ReportLocation eligibility for Huyền
SELECT u."Id"::text AS user_id, u."StoreId"::text AS jwt_store
FROM "AspNetUsers" u WHERE u."UserName" = '033189011896';

SELECT e."Id"::text AS emp_id, e."EmployeeCode", e."StoreId"::text AS emp_store, e."ApplicationUserId"::text
FROM "Employees" e WHERE e."EmployeeCode" = '033189011896';

SELECT d."EmployeeId", d."DeviceModel", d."IsAuthorized", d."AllowOutsideCheckIn", d."Deleted", d."StoreId"::text
FROM "AuthorizedMobileDevices" d
WHERE d."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND d."Deleted" IS NULL AND d."IsAuthorized" AND d."AllowOutsideCheckIn";

-- Exact AnyAsync simulation
SELECT EXISTS (
  SELECT 1 FROM "AuthorizedMobileDevices" d
  WHERE d."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
    AND d."Deleted" IS NULL AND d."IsAuthorized" AND d."AllowOutsideCheckIn"
    AND (d."EmployeeId" = '9b239775-82f1-486b-9bbc-848abd6e68d4'
      OR d."EmployeeId" = 'fb278473-8136-4d86-8cdd-c10fdd91ded7'
      OR d."EmployeeId" = '033189011896')
) AS allow_outside;

-- Active shift check (server local time in container = UTC)
SELECT s."StartTime", s."EndTime", s."Status", s."EmployeeUserId"::text
FROM "Shifts" s
WHERE s."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND s."EmployeeUserId" = '9b239775-82f1-486b-9bbc-848abd6e68d4'
  AND s."Status" = 1
ORDER BY s."StartTime" DESC LIMIT 3;
