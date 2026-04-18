-- Check if MealDishes table exists and has wrong columns
DO $$
BEGIN
    -- Drop old table with wrong column names if it exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'MealDishes') THEN
        -- Check if it has the wrong column 'CreatedOn' (old schema)
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'MealDishes' AND column_name = 'CreatedOn') THEN
            DROP TABLE "MealDishes";
            RAISE NOTICE 'Dropped MealDishes with wrong columns';
        -- Check if it's missing 'CreatedAt' column (wasn't created properly at all)
        ELSIF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'MealDishes' AND column_name = 'CreatedAt') THEN
            DROP TABLE "MealDishes";
            RAISE NOTICE 'Dropped MealDishes missing CreatedAt';
        ELSE
            RAISE NOTICE 'MealDishes already has correct schema';
        END IF;
    END IF;
END $$;

-- Create MealDishes with correct column names matching EF Entity
CREATE TABLE IF NOT EXISTS "MealDishes" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "Name" character varying(200) NOT NULL,
    "Category" character varying(100) NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "StoreId" uuid NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_MealDishes" PRIMARY KEY ("Id")
);

CREATE INDEX IF NOT EXISTS "IX_MealDishes_StoreId" ON "MealDishes" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_MealDishes_Category" ON "MealDishes" ("Category");

-- Fix MealDebts table too
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'MealDebts') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'MealDebts' AND column_name = 'CreatedOn') THEN
            DROP TABLE "MealDebts";
            RAISE NOTICE 'Dropped MealDebts with wrong columns';
        ELSIF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'MealDebts' AND column_name = 'CreatedAt') THEN
            DROP TABLE "MealDebts";
            RAISE NOTICE 'Dropped MealDebts missing CreatedAt';
        ELSE
            RAISE NOTICE 'MealDebts already has correct schema';
        END IF;
    END IF;
END $$;

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
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_MealDebts" PRIMARY KEY ("Id")
);

CREATE INDEX IF NOT EXISTS "IX_MealDebts_EmployeeUserId" ON "MealDebts" ("EmployeeUserId");
CREATE INDEX IF NOT EXISTS "IX_MealDebts_Period" ON "MealDebts" ("Period");
CREATE INDEX IF NOT EXISTS "IX_MealDebts_StoreId" ON "MealDebts" ("StoreId");

-- Verify
SELECT 'MealDishes columns:' as info;
SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'MealDishes' ORDER BY ordinal_position;
SELECT 'MealDebts columns:' as info;
SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'MealDebts' ORDER BY ordinal_position;
