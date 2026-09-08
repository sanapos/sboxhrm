SELECT "Id", "Name", "Code" FROM "Stores" WHERE "Name" ILIKE '%Trường%' OR "Code" ILIKE '%truong%';

SELECT COUNT(*) AS dev_total,
       COUNT(*) FILTER (WHERE "AllowOutsideCheckIn") AS outside_any,
       COUNT(*) FILTER (WHERE "AllowOutsideCheckIn" AND "IsAuthorized") AS outside_auth
FROM "AuthorizedMobileDevices"
WHERE "StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad' AND "Deleted" IS NULL;

SELECT "EmployeeId", "EmployeeName", "DeviceModel", "IsAuthorized", "AllowOutsideCheckIn"
FROM "AuthorizedMobileDevices"
WHERE "StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad' AND "Deleted" IS NULL
ORDER BY "AllowOutsideCheckIn" DESC, "EmployeeName";
