-- Add JourneyId and OutsideRadius columns to VisitReports
-- Links visits to journeys and tracks out-of-radius check-ins

DO $$
BEGIN
    -- Add JourneyId column if not exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'VisitReports' AND column_name = 'JourneyId') THEN
        ALTER TABLE "VisitReports" ADD COLUMN "JourneyId" uuid;
    END IF;

    -- Add OutsideRadius column if not exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'VisitReports' AND column_name = 'OutsideRadius') THEN
        ALTER TABLE "VisitReports" ADD COLUMN "OutsideRadius" boolean NOT NULL DEFAULT false;
    END IF;
END $$;

-- Create index for JourneyId lookups
CREATE INDEX IF NOT EXISTS "IX_VisitReport_Journey" ON "VisitReports" ("StoreId", "JourneyId");

-- Backfill JourneyId for existing records (match by employee + date)
UPDATE "VisitReports" vr
SET "JourneyId" = jt."Id"
FROM "JourneyTrackings" jt
WHERE vr."JourneyId" IS NULL
  AND vr."EmployeeId" = jt."EmployeeId"
  AND vr."StoreId" = jt."StoreId"
  AND DATE(vr."VisitDate") = DATE(jt."JourneyDate")
  AND jt."Deleted" IS NULL
  AND vr."Deleted" IS NULL;

SELECT 'Migration complete: JourneyId=' || COUNT(DISTINCT "JourneyId") || ' linked visits' 
FROM "VisitReports" WHERE "JourneyId" IS NOT NULL;
