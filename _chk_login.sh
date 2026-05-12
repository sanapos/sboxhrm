#!/bin/bash
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "\dt" | grep -i store

echo "=== ExpiryDate check ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT \"Code\", \"Name\", \"IsActive\", \"ExpiryDate\", \"TrialDays\", \"TrialStartDate\" FROM \"Stores\" ORDER BY \"CreatedAt\" DESC LIMIT 20;"

echo "=== EmailConfirmed check ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT \"UserName\", \"Email\", \"EmailConfirmed\", \"IsActive\", \"LockoutEnabled\", \"LockoutEnd\" FROM \"AspNetUsers\" LIMIT 20;"
