-- Add WifiBssid column to MobileAttendanceRecords table
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "WifiBssid" VARCHAR(50);
