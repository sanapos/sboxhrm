UPDATE "EmployeeLiveLocations"
SET "UpdatedAt" = NOW()
WHERE "EmployeeId" = '9b239775-82f1-486b-9bbc-848abd6e68d4'
RETURNING "UpdatedAt", "Latitude", "Longitude";
