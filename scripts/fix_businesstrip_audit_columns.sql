-- Fix BusinessTrip tables for EF Entity/AuditableEntity column expectations.
-- Use one ADD COLUMN per statement (more reliable across Postgres versions).
BEGIN;

-- Approval records inherit Entity<T> → need CreatedAt/UpdatedAt/CreatedBy/UpdatedBy
ALTER TABLE "BusinessTripAdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc');
ALTER TABLE "BusinessTripAdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedAt" timestamp without time zone NULL;
ALTER TABLE "BusinessTripAdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedBy" text NULL;
ALTER TABLE "BusinessTripAdvanceApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedBy" text NULL;

ALTER TABLE "BusinessTripSettlementApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc');
ALTER TABLE "BusinessTripSettlementApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedAt" timestamp without time zone NULL;
ALTER TABLE "BusinessTripSettlementApprovalRecords" ADD COLUMN IF NOT EXISTS "CreatedBy" text NULL;
ALTER TABLE "BusinessTripSettlementApprovalRecords" ADD COLUMN IF NOT EXISTS "UpdatedBy" text NULL;

-- Main tables: AuditableEntity LastModified
ALTER TABLE "BusinessTripCases" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripCases" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripAdvanceClaims" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripAdvanceClaims" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripSettlementClaims" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripSettlementClaims" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripExpenseCategories" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripExpenseCategories" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripExpenseLines" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripExpenseLines" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;
ALTER TABLE "BusinessTripExpenseAttachments" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone NULL;
ALTER TABLE "BusinessTripExpenseAttachments" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text NULL;

COMMIT;
