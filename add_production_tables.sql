-- Migration: Add product-based salary tables
-- ProductGroups, ProductItems, ProductPriceTiers, ProductionEntries

CREATE TABLE IF NOT EXISTS "ProductGroups" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "Name" character varying(100) NOT NULL,
    "Description" character varying(500),
    "SortOrder" integer NOT NULL DEFAULT 0,
    "StoreId" uuid,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_ProductGroups" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ProductGroups_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id")
);

CREATE TABLE IF NOT EXISTS "ProductItems" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "Code" character varying(50) NOT NULL,
    "Name" character varying(200) NOT NULL,
    "Unit" character varying(50),
    "Description" character varying(500),
    "SortOrder" integer NOT NULL DEFAULT 0,
    "ProductGroupId" uuid NOT NULL,
    "StoreId" uuid,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_ProductItems" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ProductItems_ProductGroups" FOREIGN KEY ("ProductGroupId") REFERENCES "ProductGroups"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ProductItems_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id")
);

CREATE TABLE IF NOT EXISTS "ProductPriceTiers" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "ProductItemId" uuid NOT NULL,
    "MinQuantity" integer NOT NULL DEFAULT 0,
    "MaxQuantity" integer,
    "UnitPrice" numeric NOT NULL DEFAULT 0,
    "TierLevel" integer NOT NULL DEFAULT 1,
    "StoreId" uuid,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_ProductPriceTiers" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ProductPriceTiers_ProductItems" FOREIGN KEY ("ProductItemId") REFERENCES "ProductItems"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ProductPriceTiers_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id")
);

CREATE TABLE IF NOT EXISTS "ProductionEntries" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "EmployeeId" uuid NOT NULL,
    "ProductItemId" uuid NOT NULL,
    "WorkDate" timestamp without time zone NOT NULL,
    "Quantity" numeric NOT NULL DEFAULT 0,
    "UnitPrice" numeric,
    "Amount" numeric,
    "Note" character varying(500),
    "StoreId" uuid,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_ProductionEntries" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ProductionEntries_Employees" FOREIGN KEY ("EmployeeId") REFERENCES "Employees"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ProductionEntries_ProductItems" FOREIGN KEY ("ProductItemId") REFERENCES "ProductItems"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ProductionEntries_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id")
);

-- Indexes
CREATE INDEX IF NOT EXISTS "IX_ProductItems_ProductGroupId" ON "ProductItems"("ProductGroupId");
CREATE INDEX IF NOT EXISTS "IX_ProductItems_StoreId" ON "ProductItems"("StoreId");
CREATE INDEX IF NOT EXISTS "IX_ProductPriceTiers_ProductItemId" ON "ProductPriceTiers"("ProductItemId");
CREATE INDEX IF NOT EXISTS "IX_ProductionEntries_EmployeeId" ON "ProductionEntries"("EmployeeId");
CREATE INDEX IF NOT EXISTS "IX_ProductionEntries_ProductItemId" ON "ProductionEntries"("ProductItemId");
CREATE INDEX IF NOT EXISTS "IX_ProductionEntries_WorkDate" ON "ProductionEntries"("WorkDate");
CREATE INDEX IF NOT EXISTS "IX_ProductionEntries_StoreId" ON "ProductionEntries"("StoreId");
CREATE INDEX IF NOT EXISTS "IX_ProductGroups_StoreId" ON "ProductGroups"("StoreId");
