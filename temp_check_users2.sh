docker exec zkteco_postgres psql -U postgres -d ZKTecoIntegration -c '\d "AspNetUsers"' | head -30
echo "---"
docker exec zkteco_postgres psql -U postgres -d ZKTecoIntegration -c 'SELECT "Id", "UserName", "Email", "StoreId" FROM "AspNetUsers";'
