-- Fix FK: clean up orphaned data from old MobileWorkLocations references
DELETE FROM "FieldLocationAssignments" WHERE "LocationId" NOT IN (SELECT "Id" FROM "FieldLocations");
DELETE FROM "VisitReports" WHERE "LocationId" NOT IN (SELECT "Id" FROM "FieldLocations");

-- Add FK constraints
DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_name = 'FK_FieldLocationAssignments_FieldLocations_LocationId') THEN
ALTER TABLE "FieldLocationAssignments" ADD CONSTRAINT "FK_FieldLocationAssignments_FieldLocations_LocationId" FOREIGN KEY ("LocationId") REFERENCES "FieldLocations"("Id") ON DELETE CASCADE;
END IF;
END $$;

DO $$ BEGIN
IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE constraint_name = 'FK_VisitReports_FieldLocations_LocationId') THEN
ALTER TABLE "VisitReports" ADD CONSTRAINT "FK_VisitReports_FieldLocations_LocationId" FOREIGN KEY ("LocationId") REFERENCES "FieldLocations"("Id") ON DELETE CASCADE;
END IF;
END $$;

SELECT 'FK constraints fixed!' AS result;
