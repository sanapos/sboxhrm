-- Fix ALL missing columns on field check-in tables
-- AuditableEntity requires: IsActive, LastModified, LastModifiedBy, Deleted, DeletedBy
-- Entity requires: CreatedAt, CreatedBy, UpdatedAt, UpdatedBy

-- ============ FieldLocations ============
ALTER TABLE "FieldLocations" ADD COLUMN IF NOT EXISTS "LastModified" timestamp with time zone;
ALTER TABLE "FieldLocations" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text;

-- ============ FieldLocationAssignments ============
ALTER TABLE "FieldLocationAssignments" ADD COLUMN IF NOT EXISTS "LastModified" timestamp with time zone;
ALTER TABLE "FieldLocationAssignments" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text;

-- ============ VisitReports ============
ALTER TABLE "VisitReports" ADD COLUMN IF NOT EXISTS "LastModified" timestamp with time zone;
ALTER TABLE "VisitReports" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text;

-- ============ JourneyTrackings ============
ALTER TABLE "JourneyTrackings" ADD COLUMN IF NOT EXISTS "LastModified" timestamp with time zone;
ALTER TABLE "JourneyTrackings" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text;

-- Verify
SELECT 'FieldLocations' AS tbl, column_name FROM information_schema.columns WHERE table_name='FieldLocations' ORDER BY ordinal_position;
SELECT 'FieldLocationAssignments' AS tbl, column_name FROM information_schema.columns WHERE table_name='FieldLocationAssignments' ORDER BY ordinal_position;
SELECT 'VisitReports' AS tbl, column_name FROM information_schema.columns WHERE table_name='VisitReports' ORDER BY ordinal_position;
SELECT 'JourneyTrackings' AS tbl, column_name FROM information_schema.columns WHERE table_name='JourneyTrackings' ORDER BY ordinal_position;
