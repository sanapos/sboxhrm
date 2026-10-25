-- Add VerificationMode column, replace RequireBothFaceAndGps
ALTER TABLE "MobileAttendanceSettings" ADD COLUMN IF NOT EXISTS "VerificationMode" VARCHAR(10) DEFAULT 'all';

-- Migrate existing data: RequireBothFaceAndGps=true => 'all', false => 'any'
UPDATE "MobileAttendanceSettings" SET "VerificationMode" = CASE
    WHEN "RequireBothFaceAndGps" = true THEN 'all'
    ELSE 'any'
END WHERE "VerificationMode" IS NULL OR "VerificationMode" = 'all';
