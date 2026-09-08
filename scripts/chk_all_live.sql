SELECT COUNT(*) AS total, MAX("UpdatedAt") AS latest FROM "EmployeeLiveLocations";
SELECT "EmployeeId", "Latitude", "Longitude", "UpdatedAt"
FROM "EmployeeLiveLocations"
ORDER BY "UpdatedAt" DESC
LIMIT 10;
