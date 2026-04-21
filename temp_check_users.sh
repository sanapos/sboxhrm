docker exec zkteco_postgres psql -U postgres -d ZKTecoIntegration -c 'SELECT "Id", "UserName", "Email", "FullName", "StoreId" FROM "AspNetUsers";'
