echo "=== Current DB (zkteco_postgres_data) - check Stores ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoIntegration -c 'SELECT count(*) as stores FROM "Stores";'

echo "=== Check if there are any databases in this volume ==="
docker exec zkteco_postgres psql -U postgres -c '\l'

echo "=== Check migrations applied ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoIntegration -c 'SELECT count(*) as migrations FROM "__EFMigrationsHistory";'

echo "=== Check zkteco_api_uploads volume ==="
docker run --rm -v zkteco_api_uploads:/data alpine sh -c 'ls -la /data/ 2>/dev/null | head -20'
