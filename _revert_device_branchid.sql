ALTER TABLE "Devices" DROP CONSTRAINT IF EXISTS "FK_Devices_Branches_BranchId";
DROP INDEX IF EXISTS "IX_Devices_BranchId";
ALTER TABLE "Devices" DROP COLUMN IF EXISTS "BranchId";
DELETE FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260508113709_AddDeviceBranchId';
