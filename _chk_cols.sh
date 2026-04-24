docker exec -i zkteco_postgres psql -U postgres -d ZKTecoADMS <<'SQL'
SELECT column_name FROM information_schema.columns WHERE table_name='UserRefreshTokens' ORDER BY ordinal_position;
SQL
