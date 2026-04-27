SELECT column_name, data_type FROM information_schema.columns WHERE table_name='Allowances' ORDER BY ordinal_position;
SELECT "Id","Name","Type","Amount","StartDate","EndDate" FROM "Allowances" ORDER BY "CreatedAt" DESC LIMIT 10;
