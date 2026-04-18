-- Create MealDishes master list table
CREATE TABLE IF NOT EXISTS "MealDishes" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "Name" character varying(200) NOT NULL,
    "Category" character varying(100) NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "StoreId" uuid NULL,
    "CreatedBy" uuid NULL,
    "CreatedOn" timestamp with time zone NOT NULL DEFAULT now(),
    "LastModifiedBy" uuid NULL,
    "LastModifiedOn" timestamp with time zone NULL,
    "DeletedOn" timestamp with time zone NULL,
    "DeletedBy" uuid NULL,
    CONSTRAINT "PK_MealDishes" PRIMARY KEY ("Id")
);

CREATE INDEX IF NOT EXISTS "IX_MealDishes_StoreId" ON "MealDishes" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_MealDishes_Category" ON "MealDishes" ("Category");
