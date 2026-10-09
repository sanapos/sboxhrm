-- Lịch sử lương không mất khi sửa: đính chính / phiên bản bị thay / thay đổi bị hủy
CREATE TABLE IF NOT EXISTS "SalaryProfileRevisions" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "EmployeeId" uuid NULL,
    "BenefitId" uuid NOT NULL,
    "EmployeeBenefitId" uuid NULL,
    "Kind" character varying(20) NOT NULL DEFAULT '',
    "BeforeJson" text NOT NULL DEFAULT '',
    "AfterJson" text NULL,
    "EffectiveDate" timestamp without time zone NULL,
    "EndDate" timestamp without time zone NULL
);
CREATE INDEX IF NOT EXISTS "IX_SalaryProfileRevisions_Employee" ON "SalaryProfileRevisions" ("EmployeeId", "CreatedAt");
CREATE INDEX IF NOT EXISTS "IX_SalaryProfileRevisions_Benefit" ON "SalaryProfileRevisions" ("BenefitId");
