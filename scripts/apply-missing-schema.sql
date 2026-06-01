-- Idempotent schema fixes for workFina (run when EF migrate fails mid-chain)
-- Safe to re-run.

-- Employees.ContractEndDate
ALTER TABLE "Employees" ADD COLUMN IF NOT EXISTS "ContractEndDate" timestamp without time zone NULL;

-- Payslip columns (dashboard / payroll)
ALTER TABLE "Payslips"
  ADD COLUMN IF NOT EXISTS "Allowances" numeric,
  ADD COLUMN IF NOT EXISTS "SocialInsurance" numeric,
  ADD COLUMN IF NOT EXISTS "HealthInsurance" numeric,
  ADD COLUMN IF NOT EXISTS "UnemploymentInsurance" numeric,
  ADD COLUMN IF NOT EXISTS "Tax" numeric;

-- MaintenanceWindows
CREATE TABLE IF NOT EXISTS "MaintenanceWindows" (
    "Id" uuid NOT NULL,
    "Title" text NOT NULL,
    "Message" text,
    "StartAt" timestamp without time zone NOT NULL,
    "EndAt" timestamp without time zone NOT NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL,
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    CONSTRAINT "PK_MaintenanceWindows" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_MaintenanceWindows_Active_Range"
    ON "MaintenanceWindows" ("IsActive", "StartAt", "EndAt");
ALTER TABLE "MaintenanceWindows"
  ADD COLUMN IF NOT EXISTS "AffectedModulesJson" jsonb NULL,
  ADD COLUMN IF NOT EXISTS "BlockAccess" boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "NotifyBeforeMinutesCsv" character varying(100) NULL,
  ADD COLUMN IF NOT EXISTS "NotifiedMinutesCsv" character varying(100) NULL,
  ADD COLUMN IF NOT EXISTS "StartNotified" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "EndNotified" boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "CreatedByUserId" uuid NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000';

-- SystemAnnouncements (minimal columns for background service + API)
CREATE TABLE IF NOT EXISTS "SystemAnnouncements" (
    "Id" uuid NOT NULL,
    "Title" text NOT NULL,
    "Body" text NOT NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "ScheduleAt" timestamp without time zone,
    "ExpiresAt" timestamp without time zone,
    "AudienceType" integer NOT NULL DEFAULT 0,
    "AudienceFilter" text,
    "CreatedAt" timestamp without time zone NOT NULL,
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    CONSTRAINT "PK_SystemAnnouncements" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_SystemAnnouncements_Status" ON "SystemAnnouncements" ("Status");
CREATE INDEX IF NOT EXISTS "IX_SystemAnnouncements_ScheduleAt" ON "SystemAnnouncements" ("ScheduleAt");
CREATE INDEX IF NOT EXISTS "IX_SystemAnnouncements_ExpiresAt" ON "SystemAnnouncements" ("ExpiresAt");

-- Leaves (manager dashboard leave query)
ALTER TABLE "Leaves" ADD COLUMN IF NOT EXISTS "CurrentApprovalStep" integer NOT NULL DEFAULT 0;
ALTER TABLE "Leaves" ADD COLUMN IF NOT EXISTS "TotalApprovalLevels" integer NOT NULL DEFAULT 1;

-- ShiftTemplates (daily report + dashboard)
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "OvernightCutoffTime" interval NULL;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "LateGraceMinutes" integer NOT NULL DEFAULT 0;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "EarlyLeaveGraceMinutes" integer NOT NULL DEFAULT 0;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "OvertimeMinutesThreshold" integer NOT NULL DEFAULT 0;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "ShiftType" text NULL;
