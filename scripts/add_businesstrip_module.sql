-- Business trip expense / Công tác phí (standalone — chạy an toàn nhiều lần)
BEGIN;

CREATE TABLE IF NOT EXISTS "BusinessTripCases" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CaseCode" character varying(30) NOT NULL,
    "EmployeeId" uuid NULL,
    "EmployeeUserId" uuid NULL,
    "StoreId" uuid NULL,
    "Title" character varying(300) NOT NULL,
    "Destination" character varying(300) NULL,
    "TripFromDate" timestamp without time zone NULL,
    "TripToDate" timestamp without time zone NULL,
    "Note" character varying(1000) NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "AdvanceAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "SettledAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "BalanceAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_BusinessTripCases_StoreId" ON "BusinessTripCases" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_BusinessTripCases_EmployeeId" ON "BusinessTripCases" ("EmployeeId");
CREATE INDEX IF NOT EXISTS "IX_BusinessTripCases_Status" ON "BusinessTripCases" ("Status");
CREATE INDEX IF NOT EXISTS "IX_BusinessTripCases_CaseCode" ON "BusinessTripCases" ("CaseCode");

CREATE TABLE IF NOT EXISTS "BusinessTripAdvanceClaims" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CaseId" uuid NOT NULL REFERENCES "BusinessTripCases"("Id") ON DELETE CASCADE,
    "StoreId" uuid NULL,
    "Amount" numeric(18,2) NOT NULL,
    "Reason" character varying(1000) NOT NULL,
    "Note" character varying(500) NULL,
    "RequestDate" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "Status" integer NOT NULL DEFAULT 0,
    "ApprovedById" uuid NULL,
    "ApprovedDate" timestamp without time zone NULL,
    "RejectionReason" character varying(500) NULL,
    "IsPaid" boolean NOT NULL DEFAULT false,
    "PaymentMethod" character varying(50) NULL,
    "PaidDate" timestamp without time zone NULL,
    "CashTransactionId" uuid NULL,
    "TotalApprovalLevels" integer NOT NULL DEFAULT 1,
    "CurrentApprovalStep" integer NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

CREATE TABLE IF NOT EXISTS "BusinessTripAdvanceApprovalRecords" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "AdvanceClaimId" uuid NOT NULL REFERENCES "BusinessTripAdvanceClaims"("Id") ON DELETE CASCADE,
    "StepOrder" integer NOT NULL,
    "StepName" character varying(200) NULL,
    "AssignedUserId" uuid NULL,
    "AssignedUserName" character varying(200) NULL,
    "ActualUserId" uuid NULL,
    "ActualUserName" character varying(200) NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "Note" character varying(1000) NULL,
    "ActionDate" timestamp without time zone NULL,
    "StoreId" uuid NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL
);

CREATE TABLE IF NOT EXISTS "BusinessTripSettlementClaims" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CaseId" uuid NOT NULL REFERENCES "BusinessTripCases"("Id") ON DELETE CASCADE,
    "StoreId" uuid NULL,
    "AdvanceAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "TotalAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "TotalWithInvoice" numeric(18,2) NOT NULL DEFAULT 0,
    "TotalWithoutInvoice" numeric(18,2) NOT NULL DEFAULT 0,
    "BalanceAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "SettlementType" integer NOT NULL DEFAULT 0,
    "Note" character varying(1000) NULL,
    "SubmittedAt" timestamp without time zone NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "ApprovedById" uuid NULL,
    "ApprovedDate" timestamp without time zone NULL,
    "RejectionReason" character varying(500) NULL,
    "IsExtraPaid" boolean NOT NULL DEFAULT false,
    "ExtraPaymentMethod" character varying(50) NULL,
    "ExtraPaidDate" timestamp without time zone NULL,
    "ExtraCashTransactionId" uuid NULL,
    "SurplusPaymentTransactionId" uuid NULL,
    "SurplusAdvanceRequestId" uuid NULL,
    "TotalApprovalLevels" integer NOT NULL DEFAULT 1,
    "CurrentApprovalStep" integer NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

CREATE TABLE IF NOT EXISTS "BusinessTripSettlementApprovalRecords" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "SettlementClaimId" uuid NOT NULL REFERENCES "BusinessTripSettlementClaims"("Id") ON DELETE CASCADE,
    "StepOrder" integer NOT NULL,
    "StepName" character varying(200) NULL,
    "AssignedUserId" uuid NULL,
    "AssignedUserName" character varying(200) NULL,
    "ActualUserId" uuid NULL,
    "ActualUserName" character varying(200) NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "Note" character varying(1000) NULL,
    "ActionDate" timestamp without time zone NULL,
    "StoreId" uuid NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL
);

CREATE TABLE IF NOT EXISTS "BusinessTripExpenseCategories" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NULL,
    "Code" character varying(50) NOT NULL,
    "Name" character varying(200) NOT NULL,
    "Description" character varying(500) NULL,
    "MaxAmountPerLine" numeric(18,2) NULL,
    "MaxAmountPerMonth" numeric(18,2) NULL,
    "RequiresInvoice" boolean NOT NULL DEFAULT false,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_BusinessTripExpenseCategories_Store_Code"
    ON "BusinessTripExpenseCategories" ("StoreId", "Code");

CREATE TABLE IF NOT EXISTS "BusinessTripExpenseLines" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "SettlementClaimId" uuid NOT NULL REFERENCES "BusinessTripSettlementClaims"("Id") ON DELETE CASCADE,
    "CategoryId" uuid NULL REFERENCES "BusinessTripExpenseCategories"("Id") ON DELETE SET NULL,
    "ExpenseDate" timestamp without time zone NOT NULL,
    "Amount" numeric(18,2) NOT NULL,
    "Description" character varying(500) NULL,
    "Note" character varying(500) NULL,
    "HasInvoice" boolean NOT NULL DEFAULT false,
    "InvoiceNumber" character varying(100) NULL,
    "InvoiceDate" timestamp without time zone NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

CREATE TABLE IF NOT EXISTS "BusinessTripExpenseAttachments" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "LineId" uuid NOT NULL REFERENCES "BusinessTripExpenseLines"("Id") ON DELETE CASCADE,
    "FileName" character varying(300) NOT NULL,
    "FileUrl" character varying(1000) NOT NULL,
    "ContentType" character varying(100) NULL,
    "FileSize" bigint NULL,
    "AttachmentType" integer NOT NULL DEFAULT 0,
    "StoreId" uuid NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder", "CreatedAt")
SELECT '11111111-1111-1111-1111-111111111085'::uuid,
       'BusinessTripExpense', 'Công tác phí', 'Ứng công tác, hoạch toán chi phí đi công tác', 85, NOW()
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'BusinessTripExpense');

ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "TravelSalaryMode" character varying(30) NULL;
ALTER TABLE "SalaryProfiles" ADD COLUMN IF NOT EXISTS "TravelFixedHourlyRate" numeric NULL;

-- AuditableEntity: EF maps LastModified / LastModifiedBy (existing DBs from first deploy)
ALTER TABLE "BusinessTripCases" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripCases" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripAdvanceClaims" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripAdvanceClaims" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripSettlementClaims" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripSettlementClaims" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripSettlementClaims" ADD COLUMN IF NOT EXISTS "SurplusAdvanceRequestId" uuid NULL;
ALTER TABLE "BusinessTripExpenseCategories" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripExpenseCategories" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripExpenseLines" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripExpenseLines" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripExpenseAttachments" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripExpenseAttachments" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;

-- Approval records inherit Entity<T> → CreatedAt/UpdatedAt/CreatedBy/UpdatedBy
ALTER TABLE "BusinessTripAdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc');
ALTER TABLE "BusinessTripAdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedAt" timestamp without time zone NULL;
ALTER TABLE "BusinessTripAdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedBy" text NULL;
ALTER TABLE "BusinessTripAdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedBy" text NULL;
ALTER TABLE "BusinessTripSettlementApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc');
ALTER TABLE "BusinessTripSettlementApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedAt" timestamp without time zone NULL;
ALTER TABLE "BusinessTripSettlementApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedBy" text NULL;
ALTER TABLE "BusinessTripSettlementApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedBy" text NULL;

INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder", "CreatedAt")
SELECT '11111111-1111-1111-1111-111111111086'::uuid,
       'BusinessTripReport', 'Báo cáo công tác phí', 'Tổng hợp ứng công tác, hoạch toán chi phí', 54, NOW()
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'BusinessTripReport');

-- Gói HRM/Full: thêm module công tác phí (không áp dụng gói POS thuần)
UPDATE "ServicePackages" sp
SET "AllowedModules" = (
    SELECT COALESCE(jsonb_agg(to_jsonb(m) ORDER BY m), '[]'::jsonb)::text
    FROM (
        SELECT DISTINCT trim(both '"' from elem::text) AS m
        FROM jsonb_array_elements_text(sp."AllowedModules"::jsonb) AS elem
        UNION
        SELECT 'BusinessTripExpense'
        UNION
        SELECT 'BusinessTripReport'
    ) u
    WHERE m <> ''
)
WHERE sp."Name" <> 'Sbox POS'
  AND (
      sp."AllowedModules" NOT LIKE '%BusinessTripExpense%'
      OR sp."AllowedModules" NOT LIKE '%BusinessTripReport%'
  );

COMMIT;
