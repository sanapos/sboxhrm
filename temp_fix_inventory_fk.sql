UPDATE "AssetInventories" SET "ResponsibleUserId" = NULL WHERE "ResponsibleUserId" IS NOT NULL AND "ResponsibleUserId" NOT IN (SELECT "Id" FROM "Employees");
ALTER TABLE "AssetInventories" ADD CONSTRAINT "FK_AssetInventories_Employees_ResponsibleUserId" FOREIGN KEY ("ResponsibleUserId") REFERENCES "Employees"("Id") ON DELETE SET NULL;
SELECT conname FROM pg_constraint WHERE conrelid = 'AssetInventories'::regclass AND contype = 'f';
