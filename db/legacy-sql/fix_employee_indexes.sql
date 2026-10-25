-- Fix Employee unique indexes to be per-store (composite with StoreId)
-- Previously these were global, causing 500 errors when same EmployeeCode/CompanyEmail exists across stores

-- Drop old global unique indexes (if they exist)
DROP INDEX IF EXISTS "IX_Employees_EmployeeCode";
DROP INDEX IF EXISTS "IX_Employees_CompanyEmail";

-- Create new composite unique indexes scoped by StoreId
CREATE UNIQUE INDEX "IX_Employees_StoreId_EmployeeCode" ON "Employees" ("StoreId", "EmployeeCode");
CREATE UNIQUE INDEX "IX_Employees_StoreId_CompanyEmail" ON "Employees" ("StoreId", "CompanyEmail");
