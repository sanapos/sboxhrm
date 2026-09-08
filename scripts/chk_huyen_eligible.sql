-- Eligibility simulation for Huyền report-location
WITH emp AS (
  SELECT e."Id"::text AS emp_id, e."ApplicationUserId"::text AS app_user_id, e."EmployeeCode", e."StoreId"
  FROM "Employees" e WHERE e."EmployeeCode" = '033189011896'
)
SELECT 'devices' AS kind, amd."EmployeeId", amd."DeviceModel", amd."IsAuthorized", amd."AllowOutsideCheckIn"
FROM "AuthorizedMobileDevices" amd, emp
WHERE amd."StoreId" = emp."StoreId" AND amd."Deleted" IS NULL
  AND amd."EmployeeId" IN (emp.emp_id, emp.app_user_id, emp."EmployeeCode");

WITH emp AS (
  SELECT e."ApplicationUserId", e."StoreId" FROM "Employees" e WHERE e."EmployeeCode" = '033189011896'
)
SELECT EXISTS (
  SELECT 1 FROM "AuthorizedMobileDevices" d, emp
  WHERE d."StoreId" = emp."StoreId" AND d."Deleted" IS NULL AND d."IsAuthorized"
    AND d."AllowOutsideCheckIn"
    AND d."EmployeeId" IN (
      emp."ApplicationUserId"::text,
      (SELECT "Id"::text FROM "Employees" WHERE "EmployeeCode"='033189011896'),
      '033189011896'
    )
) AS allow_outside_eligible;
