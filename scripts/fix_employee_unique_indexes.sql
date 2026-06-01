-- Fix employee unique indexes: per-store (not global CompanyEmail)
DROP INDEX IF EXISTS "IX_Employees_CompanyEmail";
DROP INDEX IF EXISTS "IX_Employees_EmployeeCode";

CREATE UNIQUE INDEX IF NOT EXISTS "IX_Employees_StoreId_CompanyEmail"
  ON "Employees" ("StoreId", "CompanyEmail");

CREATE UNIQUE INDEX IF NOT EXISTS "IX_Employees_StoreId_EmployeeCode"
  ON "Employees" ("StoreId", "EmployeeCode");
