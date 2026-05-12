ALTER TABLE "Devices" ADD COLUMN IF NOT EXISTS "BranchId" uuid;
CREATE INDEX IF NOT EXISTS "IX_Devices_BranchId" ON "Devices" ("BranchId");
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_Devices_Branches_BranchId') THEN
    ALTER TABLE "Devices" ADD CONSTRAINT "FK_Devices_Branches_BranchId" FOREIGN KEY ("BranchId") REFERENCES "Branches"("Id") ON DELETE SET NULL;
  END IF;
END $$;
INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES ('20260508113709_AddDeviceBranchId', '8.0.0')
ON CONFLICT DO NOTHING;
