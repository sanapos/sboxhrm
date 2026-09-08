SELECT d."DeviceName", d."DeviceId", d."AllowOutsideCheckIn", d."IsAuthorized", d."UpdatedAt"
FROM "AuthorizedMobileDevices" d
WHERE d."EmployeeId" = 'fb278473-8136-4d86-8cdd-c10fdd91ded7' AND d."Deleted" IS NULL;

SELECT "EmployeeId", "Latitude", "Longitude", "UpdatedAt",
       EXTRACT(EPOCH FROM (NOW() AT TIME ZONE 'UTC' - "UpdatedAt"))/60 AS age_min
FROM "EmployeeLiveLocations"
WHERE "StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad';
