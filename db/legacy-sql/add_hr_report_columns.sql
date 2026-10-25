-- Add Hometown and EducationLevel columns to Employees table
ALTER TABLE "Employees" ADD COLUMN IF NOT EXISTS "Hometown" character varying(100) NULL;
ALTER TABLE "Employees" ADD COLUMN IF NOT EXISTS "EducationLevel" character varying(100) NULL;
