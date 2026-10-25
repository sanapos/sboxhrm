-- Adds missing columns to Allowances table to match Allowance entity.
-- Entity adds: EmployeeIds (text), StartDate (timestamp), EndDate (timestamp).
-- Without these the API throws Npgsql 42703 "column a.EmployeeIds does not exist"
-- on every GET/POST/PUT /api/allowances request.

ALTER TABLE "Allowances"
    ADD COLUMN IF NOT EXISTS "EmployeeIds" text NULL,
    ADD COLUMN IF NOT EXISTS "StartDate"   timestamp without time zone NULL,
    ADD COLUMN IF NOT EXISTS "EndDate"     timestamp without time zone NULL;
