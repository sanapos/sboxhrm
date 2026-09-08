SELECT "DeviceId", "DeviceName", "EmployeeId", "AllowOutsideCheckIn", "IsAuthorized"
FROM "AuthorizedMobileDevices"
WHERE "EmployeeName" ILIKE '%Huyền%' AND "Deleted" IS NULL;

SELECT "EmployeeId", "Latitude", "Longitude", "UpdatedAt",
       NOW() AS server_now,
       EXTRACT(EPOCH FROM (NOW() - "UpdatedAt"))/60 AS minutes_ago
FROM "EmployeeLiveLocations"
WHERE "EmployeeId" = '9b239775-82f1-486b-9bbc-848abd6e68d4';
