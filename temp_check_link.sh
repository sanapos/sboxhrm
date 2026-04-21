echo "=== Check if Employees table has AppUserId or similar ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '\d "Employees"' | grep -i -E 'user|app|account'

echo "=== Check EmployeeWorkingInfos ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '\d "EmployeeWorkingInfos"' | head -15

echo "=== Also check Employee for Nguyen Van Linh ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '
SELECT "Id", "EmployeeCode", "FirstName", "CompanyEmail" FROM "Employees" 
WHERE "FirstName" = '\''Linh'\'' AND "StoreId" = (SELECT "Id" FROM "Stores" WHERE "Code" = '\''demo'\'' LIMIT 1);
'

echo "=== Check CurrentUserId logic - what is logged in user for journey ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '
SELECT j."EmployeeId", j."Status", length(j."RoutePointsJson") as pts
FROM "JourneyTrackings" j WHERE j."JourneyDate" >= CURRENT_DATE;
'
