SELECT "DeviceId", "DeviceName", "DeviceModel", "IsAuthorized", "AllowOutsideCheckIn",
       "LastUsedAt", "UpdatedAt"
FROM "AuthorizedMobileDevices"
WHERE "EmployeeId"='53c1bcbd-f8c2-47da-bca3-684b80a08c04' AND "Deleted" IS NULL;
