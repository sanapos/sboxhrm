echo "=== Check which volume current container uses ==="
docker inspect zkteco_postgres | grep -A5 '"Mounts"' | head -10
echo "=== Check api_src_postgres_data volume ==="
docker run --rm -v api_src_postgres_data:/data alpine sh -c 'ls /data/pgdata/ 2>/dev/null | head -10 || echo "empty or no pgdata"'
echo "=== Check zkteco_postgres_data volume ==="
docker run --rm -v zkteco_postgres_data:/data alpine sh -c 'ls /data/pgdata/ 2>/dev/null | head -10 || echo "empty or no pgdata"'
