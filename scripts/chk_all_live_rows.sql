SELECT "StoreId", "EmployeeId", "Latitude", "Longitude", "UpdatedAt"
FROM "EmployeeLiveLocations"
WHERE "EmployeeId" IN (
  'fb278473-8136-4d86-8cdd-c10fdd91ded7',
  '9b239775-82f1-486b-9bbc-848abd6e68d4',
  '033189011896'
)
ORDER BY "UpdatedAt" DESC;

SELECT COUNT(*) AS total FROM "EmployeeLiveLocations";
