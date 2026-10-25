-- Migration: Add ContractEndDate to Employees table
-- Run this on the production database BEFORE deploying the new API

ALTER TABLE "Employees" ADD COLUMN IF NOT EXISTS "ContractEndDate" timestamp without time zone NULL;

-- Verify
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'Employees' AND column_name = 'ContractEndDate';
