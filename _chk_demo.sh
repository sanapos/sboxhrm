docker exec -i zkteco_postgres psql -U postgres -d ZKTecoADMS <<'SQL'
SELECT "Id","Name","Code","LicenseType","ExpiryDate","TrialStartDate","TrialDays","ServicePackageId","CreatedAt"
FROM "Stores" WHERE "Code"='demo' OR "Name"='demo';
SQL
