#!/bin/bash
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c 'SELECT COUNT(*) as total, COUNT("ApplicationUserId") as has_user FROM "Employees" WHERE "IsActive" = true;'
echo "---"
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c 'SELECT "Id", "FirstName", "LastName", "ApplicationUserId" FROM "Employees" WHERE "IsActive" = true LIMIT 5;'
