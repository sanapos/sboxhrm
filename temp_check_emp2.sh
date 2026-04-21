echo "=== Employees in demo store ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '
SELECT "Id", "EmployeeCode", "FirstName", "LastName", "UserId"
FROM "Employees"
WHERE "StoreId" = (SELECT "Id" FROM "Stores" WHERE "Code" = '\''demo'\'' LIMIT 1)
LIMIT 20;
'

echo "=== EmployeeLiveLocations ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '
SELECT * FROM "EmployeeLiveLocations" LIMIT 10;
'

echo "=== JourneyTrackings today ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '
SELECT "EmployeeId", "Status", "StartTime", length("RoutePointsJson") as route_len
FROM "JourneyTrackings" 
WHERE "JourneyDate" >= CURRENT_DATE
LIMIT 10;
'
