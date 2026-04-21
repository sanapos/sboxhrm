echo "=== Employee columns ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '\d "Employees"' | head -20

echo "=== Employees in demo store ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '
SELECT "Id", "EmployeeCode", "FirstName", "LastName"
FROM "Employees"
WHERE "StoreId" = (SELECT "Id" FROM "Stores" WHERE "Code" = '\''demo'\'' LIMIT 1)
LIMIT 20;
'

echo "=== User demo@gmail.com ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '
SELECT "Id", "UserName", "StoreId" FROM "AspNetUsers" WHERE "Email" = '\''demo@gmail.com'\'';
'
