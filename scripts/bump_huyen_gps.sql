UPDATE "EmployeeLiveLocations"
SET "UpdatedAt" = NOW() AT TIME ZONE 'UTC',
    "Latitude" = 16.05,
    "Longitude" = 108.16
WHERE "EmployeeId" = '9b239775-82f1-486b-9bbc-848abd6e68d4';

SELECT "EmployeeId", "Latitude", "UpdatedAt" FROM "EmployeeLiveLocations";
