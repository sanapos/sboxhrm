-- Migration: Add Google Sheet config columns to KpiEmployeeTargets
-- Run this against the PostgreSQL database

ALTER TABLE "KpiEmployeeTargets" ADD COLUMN IF NOT EXISTS "GoogleSheetUrl" varchar(500) NULL;
ALTER TABLE "KpiEmployeeTargets" ADD COLUMN IF NOT EXISTS "GoogleSheetName" varchar(200) NULL;
ALTER TABLE "KpiEmployeeTargets" ADD COLUMN IF NOT EXISTS "GoogleCellPosition" varchar(20) NULL;
ALTER TABLE "KpiEmployeeTargets" ADD COLUMN IF NOT EXISTS "AutoSyncEnabled" boolean NOT NULL DEFAULT false;
ALTER TABLE "KpiEmployeeTargets" ADD COLUMN IF NOT EXISTS "SyncIntervalMinutes" integer NOT NULL DEFAULT 60;
