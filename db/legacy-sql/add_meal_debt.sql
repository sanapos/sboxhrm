-- Add PricePerMeal to MealSessions
ALTER TABLE "MealSessions" ADD COLUMN IF NOT EXISTS "PricePerMeal" decimal NOT NULL DEFAULT 0;

-- Create MealDebts table
-- First drop if columns wrong
DROP TABLE IF EXISTS "MealDebts";

CREATE TABLE IF NOT EXISTS "MealDebts" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "EmployeeUserId" uuid NOT NULL,
    "EmployeeName" character varying(256) NOT NULL DEFAULT '',
    "Type" integer NOT NULL DEFAULT 0,
    "Amount" decimal NOT NULL DEFAULT 0,
    "Date" timestamp without time zone NOT NULL,
    "MealSessionId" uuid NULL,
    "Period" character varying(10) NULL,
    "Note" character varying(500) NULL,
    "RecordedByUserId" uuid NULL,
    "RecordedByName" character varying(256) NULL,
    "StoreId" uuid NULL,
    -- AuditableEntity fields
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    -- Entity fields
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_MealDebts" PRIMARY KEY ("Id")
);

CREATE INDEX IF NOT EXISTS "IX_MealDebts_EmployeeUserId" ON "MealDebts" ("EmployeeUserId");
CREATE INDEX IF NOT EXISTS "IX_MealDebts_Period" ON "MealDebts" ("Period");
CREATE INDEX IF NOT EXISTS "IX_MealDebts_StoreId" ON "MealDebts" ("StoreId");
