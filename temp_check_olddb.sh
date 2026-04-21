echo "=== Check old ZKTecoADMS database ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '\dt' 2>/dev/null | head -30
echo "=== Check Stores in old DB ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c 'SELECT "Id", "Name", "Code", "IsActive", "ExpiryDate" FROM "Stores";' 2>/dev/null
echo "=== Check users in old DB ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c 'SELECT "Id", "UserName", "Email", "StoreId", "IsActive" FROM "AspNetUsers" LIMIT 10;' 2>/dev/null
