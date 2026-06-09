-- Chốt lương theo EmployeeId (NV không cần tài khoản đăng nhập)
ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "EmployeeId" uuid NULL;

UPDATE "Payslips" p
SET "EmployeeId" = e."Id"
FROM "Employees" e
WHERE e."ApplicationUserId" = p."EmployeeUserId"
  AND p."EmployeeId" IS NULL;

ALTER TABLE "Payslips" ALTER COLUMN "EmployeeUserId" DROP NOT NULL;

DROP INDEX IF EXISTS "IX_Payslips_EmployeeUserId_Year_Month";

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_Payslips_Employees_EmployeeId'
  ) THEN
    ALTER TABLE "Payslips"
      ADD CONSTRAINT "FK_Payslips_Employees_EmployeeId"
      FOREIGN KEY ("EmployeeId") REFERENCES "Employees" ("Id") ON DELETE RESTRICT;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "Payslips" WHERE "EmployeeId" IS NULL) THEN
    RAISE EXCEPTION 'Payslips.EmployeeId backfill incomplete — fix orphan rows first';
  END IF;
END $$;

ALTER TABLE "Payslips" ALTER COLUMN "EmployeeId" SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS "IX_Payslips_EmployeeId_Year_Month"
  ON "Payslips" ("EmployeeId", "Year", "Month");
