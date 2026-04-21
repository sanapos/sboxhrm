echo "=== Check api_src_postgres_data for data ==="
docker run --rm -v api_src_postgres_data:/data alpine sh -c 'ls -la /data/ 2>/dev/null; echo "---"; ls -la /data/pgdata/ 2>/dev/null || echo "no pgdata dir"'
