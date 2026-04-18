-- Add PricePerMeal to MealSessions
ALTER TABLE "MealSessions" ADD COLUMN IF NOT EXISTS "PricePerMeal" decimal NOT NULL DEFAULT 0;

-- Create MealDebts table
CREATE TABLE IF NOT EXISTS "MealDebts" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "EmployeeUserId" uuid NOT NULL,
    "EmployeeName" character varying(256) NOT NULL DEFAULT '',
    "Type" integer NOT NULL DEFAULT 0,
    "Amount" decimal NOT NULL DEFAULT 0,
    "Date" timestamp with time zone NOT NULL,
    "MealSessionId" uuid NULL,
    "Period" character varying(7) NULL,
    "Note" character varying(500) NULL,
    "RecordedByUserId" uuid NULL,
    "RecordedByName" character varying(256) NULL,
    "StoreId" uuid NULL,
    "CreatedBy" uuid NULL,
    "CreatedOn" timestamp with time zone NOT NULL DEFAULT now(),
    "LastModifiedBy" uuid NULL,
    "LastModifiedOn" timestamp with time zone NULL,
    "DeletedOn" timestamp with time zone NULL,
    "DeletedBy" uuid NULL,
    CONSTRAINT "PK_MealDebts" PRIMARY KEY ("Id")
);

CREATE INDEX IF NOT EXISTS "IX_MealDebts_EmployeeUserId" ON "MealDebts" ("EmployeeUserId");
CREATE INDEX IF NOT EXISTS "IX_MealDebts_Period" ON "MealDebts" ("Period");
CREATE INDEX IF NOT EXISTS "IX_MealDebts_StoreId" ON "MealDebts" ("StoreId");
