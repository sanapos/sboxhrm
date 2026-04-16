-- Migration: Add ServicePackages table and store package/trial fields
-- Database: PostgreSQL

-- 1. Create ServicePackages table
CREATE TABLE IF NOT EXISTS "ServicePackages" (
    "Id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "Name" varchar(200) NOT NULL,
    "Description" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "DefaultDurationDays" integer NOT NULL DEFAULT 30,
    "MaxUsers" integer NOT NULL DEFAULT 10,
    "MaxDevices" integer NOT NULL DEFAULT 2,
    "AllowedModules" text NOT NULL DEFAULT '[]',
    "CreatedAt" timestamp NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp,
    "CreatedBy" text,
    "UpdatedBy" text
);

-- 2. Add new columns to Stores table
ALTER TABLE "Stores" ADD COLUMN IF NOT EXISTS "ServicePackageId" uuid REFERENCES "ServicePackages"("Id") ON DELETE SET NULL;
ALTER TABLE "Stores" ADD COLUMN IF NOT EXISTS "TrialStartDate" timestamp;
ALTER TABLE "Stores" ADD COLUMN IF NOT EXISTS "TrialDays" integer NOT NULL DEFAULT 14;

-- 3. Set TrialStartDate for existing stores that are Trial
UPDATE "Stores" SET "TrialStartDate" = "CreatedAt" WHERE "TrialStartDate" IS NULL;

-- 4. Create a default "Dùng thử" (Trial) package
INSERT INTO "ServicePackages" ("Id", "Name", "Description", "IsActive", "DefaultDurationDays", "MaxUsers", "MaxDevices", "AllowedModules", "CreatedAt")
VALUES (
    gen_random_uuid(),
    'Dùng thử',
    'Gói dùng thử 14 ngày - đầy đủ chức năng',
    true,
    14,
    10,
    2,
    '["Dashboard","Employee","Department","Attendance","AttendanceCorrection","Leave","Overtime","Shift","WorkSchedule","ShiftSwap","Salary","Payslip","Allowance","Advance","Insurance","Tax","Benefit","Device","DeviceUser","Report","KPI","Task","Asset","CashTransaction","BankAccount","HrDocument","Holiday","Notification","Communication","Geofence","OrgChart","Settings","Role","UserManagement"]',
    NOW()
);

-- 5. Create index
CREATE INDEX IF NOT EXISTS "IX_Stores_ServicePackageId" ON "Stores" ("ServicePackageId");
