-- Huyền live status snapshot
SELECT NOW() AT TIME ZONE 'UTC' AS utc_now;

SELECT d."DeviceName", d."DeviceId", d."EmployeeId", d."AllowOutsideCheckIn", d."IsAuthorized"
FROM "AuthorizedMobileDevices" d
WHERE d."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND d."Deleted" IS NULL
  AND d."EmployeeId" = 'fb278473-8136-4d86-8cdd-c10fdd91ded7';

SELECT "EmployeeId", "Latitude", "Longitude", "UpdatedAt",
       ROUND(EXTRACT(EPOCH FROM (NOW() AT TIME ZONE 'UTC' - "UpdatedAt"))/60, 1) AS age_min
FROM "EmployeeLiveLocations"
WHERE "StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND "EmployeeId" = 'fb278473-8136-4d86-8cdd-c10fdd91ded7';
