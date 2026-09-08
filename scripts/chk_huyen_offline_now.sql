-- Huyền: thiết bị + GPS + thời gian
SELECT d."DeviceName", d."DeviceId", d."AllowOutsideCheckIn", d."IsAuthorized", d."UpdatedAt"
FROM "AuthorizedMobileDevices" d
WHERE d."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND d."Deleted" IS NULL
  AND d."EmployeeId" = 'fb278473-8136-4d86-8cdd-c10fdd91ded7';

SELECT "EmployeeId", "Latitude", "Longitude", "UpdatedAt",
       ROUND(EXTRACT(EPOCH FROM (NOW() AT TIME ZONE 'UTC' - "UpdatedAt"))/60, 1) AS age_min
FROM "EmployeeLiveLocations"
WHERE "StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND "EmployeeId" IN (
    'fb278473-8136-4d86-8cdd-c10fdd91ded7',
    '9b239775-82f1-486b-9bbc-848abd6e68d4'
  );

SELECT e."Id", e."EmployeeCode", e."ApplicationUserId"
FROM "Employees" e
WHERE e."Id" = 'fb278473-8136-4d86-8cdd-c10fdd91ded7';
