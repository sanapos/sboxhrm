-- Raise mobile attendance daily punch limit default from 4 to 10
-- Apply for existing settings rows and future inserted rows.

UPDATE "MobileAttendanceSettings"
SET "MaxPunchesPerDay" = 10
WHERE "MaxPunchesPerDay" = 4;

ALTER TABLE "MobileAttendanceSettings"
ALTER COLUMN "MaxPunchesPerDay" SET DEFAULT 10;
