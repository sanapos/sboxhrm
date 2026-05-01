SELECT column_name FROM information_schema.columns WHERE table_name='Employees' AND column_name ILIKE '%shift%';
SELECT column_name FROM information_schema.columns WHERE table_name='EmployeeBenefits' AND column_name ILIKE '%shift%';
SELECT column_name FROM information_schema.columns WHERE table_name='Benefits' AND column_name ILIKE '%shift%';
