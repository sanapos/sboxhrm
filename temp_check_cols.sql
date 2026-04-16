-- Check employee columns
SELECT column_name FROM information_schema.columns WHERE table_name = 'Employees' ORDER BY ordinal_position;
