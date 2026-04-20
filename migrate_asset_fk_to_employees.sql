-- Migration: Change Asset FK constraints from AspNetUsers to Employees
-- This allows assigning assets to ANY employee, even those without login accounts

BEGIN;

-- Step 1: Convert existing data - replace ApplicationUserId with EmployeeId
-- Assets.CurrentAssigneeId: ApplicationUserId → EmployeeId
UPDATE "Assets" a
SET "CurrentAssigneeId" = e."Id"
FROM "Employees" e
WHERE a."CurrentAssigneeId" = e."ApplicationUserId"
  AND a."CurrentAssigneeId" IS NOT NULL;

-- AssetTransfers.ToUserId: ApplicationUserId → EmployeeId
UPDATE "AssetTransfers" t
SET "ToUserId" = e."Id"
FROM "Employees" e
WHERE t."ToUserId" = e."ApplicationUserId"
  AND t."ToUserId" IS NOT NULL;

-- AssetTransfers.FromUserId: ApplicationUserId → EmployeeId
UPDATE "AssetTransfers" t
SET "FromUserId" = e."Id"
FROM "Employees" e
WHERE t."FromUserId" = e."ApplicationUserId"
  AND t."FromUserId" IS NOT NULL;

-- Step 2: NULL out any orphaned references (ApplicationUserIds that don't match any Employee)
UPDATE "Assets" SET "CurrentAssigneeId" = NULL
WHERE "CurrentAssigneeId" IS NOT NULL
  AND "CurrentAssigneeId" NOT IN (SELECT "Id" FROM "Employees");

UPDATE "AssetTransfers" SET "ToUserId" = NULL
WHERE "ToUserId" IS NOT NULL
  AND "ToUserId" NOT IN (SELECT "Id" FROM "Employees");

UPDATE "AssetTransfers" SET "FromUserId" = NULL
WHERE "FromUserId" IS NOT NULL
  AND "FromUserId" NOT IN (SELECT "Id" FROM "Employees");

-- Step 3: Drop old FK constraints pointing to AspNetUsers
ALTER TABLE "Assets" DROP CONSTRAINT IF EXISTS "FK_Assets_AspNetUsers_CurrentAssigneeId";
ALTER TABLE "AssetTransfers" DROP CONSTRAINT IF EXISTS "FK_AssetTransfers_AspNetUsers_ToUserId";
ALTER TABLE "AssetTransfers" DROP CONSTRAINT IF EXISTS "FK_AssetTransfers_AspNetUsers_FromUserId";

-- Step 4: Add new FK constraints pointing to Employees
ALTER TABLE "Assets" ADD CONSTRAINT "FK_Assets_Employees_CurrentAssigneeId"
    FOREIGN KEY ("CurrentAssigneeId") REFERENCES "Employees"("Id") ON DELETE SET NULL;

ALTER TABLE "AssetTransfers" ADD CONSTRAINT "FK_AssetTransfers_Employees_ToUserId"
    FOREIGN KEY ("ToUserId") REFERENCES "Employees"("Id") ON DELETE SET NULL;

ALTER TABLE "AssetTransfers" ADD CONSTRAINT "FK_AssetTransfers_Employees_FromUserId"
    FOREIGN KEY ("FromUserId") REFERENCES "Employees"("Id") ON DELETE SET NULL;

COMMIT;
