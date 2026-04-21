docker exec zkteco_postgres psql -U postgres -d ZKTecoIntegration -c 'SELECT "Id", "Name", "StoreCode", "IsActive", "ExpiryDate" FROM "Stores" LIMIT 10;'
