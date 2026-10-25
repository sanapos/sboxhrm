-- Drop old table if columns are wrong, then recreate
DROP TABLE IF EXISTS "MealDishes";

-- Create MealDishes master list table
CREATE TABLE IF NOT EXISTS "MealDishes" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "Name" character varying(200) NOT NULL,
    "Category" character varying(100) NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
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
    CONSTRAINT "PK_MealDishes" PRIMARY KEY ("Id")
);

CREATE INDEX IF NOT EXISTS "IX_MealDishes_StoreId" ON "MealDishes" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_MealDishes_Category" ON "MealDishes" ("Category");
