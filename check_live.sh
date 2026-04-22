#!/bin/bash
echo "=== count ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT COUNT(*) FROM \"EmployeeLiveLocations\";"
echo "=== recent 10 ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT * FROM \"EmployeeLiveLocations\" ORDER BY \"UpdatedAt\" DESC LIMIT 10;"
echo "=== last 15 min ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT COUNT(*) FROM \"EmployeeLiveLocations\" WHERE \"UpdatedAt\" > NOW() - INTERVAL '15 minutes';"
echo "=== columns ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c "SELECT column_name FROM information_schema.columns WHERE table_name='EmployeeLiveLocations' ORDER BY ordinal_position;"
