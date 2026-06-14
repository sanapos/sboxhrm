-- Chuẩn hóa AuthorizedMobileDevices.EmployeeId -> Employees.Id (chạy an toàn nhiều lần)
UPDATE "AuthorizedMobileDevices" amd
SET "EmployeeId" = e."Id"::text,
    "UpdatedAt" = NOW() AT TIME ZONE 'UTC'
FROM "Employees" e
WHERE amd."Deleted" IS NULL
  AND e."StoreId" = amd."StoreId"
  AND e."Deleted" IS NULL
  AND (
    e."Id"::text = amd."EmployeeId"
    OR e."EmployeeCode" = amd."EmployeeId"
    OR e."ApplicationUserId"::text = amd."EmployeeId"
  )
  AND amd."EmployeeId" IS DISTINCT FROM e."Id"::text;
