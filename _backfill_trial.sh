docker exec -i zkteco_postgres psql -U postgres -d ZKTecoADMS <<'SQL'
UPDATE "Stores"
SET "TrialStartDate" = "CreatedAt"
WHERE "TrialStartDate" IS NULL AND "ExpiryDate" IS NULL AND "TrialDays" IS NOT NULL;
SELECT "Name","TrialStartDate","TrialDays","ExpiryDate" FROM "Stores";
SQL
