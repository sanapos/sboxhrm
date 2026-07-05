-- Bảng giá POS (KiotViet)
CREATE TABLE IF NOT EXISTS "PosPriceLists" (
    "Id" uuid PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "Name" character varying(100) NOT NULL,
    "IsDefault" boolean NOT NULL DEFAULT false,
    "IsActive" boolean NOT NULL DEFAULT true,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" character varying(256),
    "UpdatedAt" timestamp with time zone,
    "UpdatedBy" character varying(256),
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp with time zone,
    "DeletedBy" text
);

CREATE INDEX IF NOT EXISTS "IX_PosPriceLists_StoreId_Name"
    ON "PosPriceLists" ("StoreId", "Name");

CREATE TABLE IF NOT EXISTS "PosPriceListItems" (
    "Id" uuid PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "PriceListId" uuid NOT NULL REFERENCES "PosPriceLists"("Id") ON DELETE CASCADE,
    "ProductId" uuid NOT NULL REFERENCES "PosProducts"("Id") ON DELETE CASCADE,
    "VariantId" uuid NULL REFERENCES "PosProductVariants"("Id") ON DELETE SET NULL,
    "UnitId" uuid NULL REFERENCES "PosProductUnits"("Id") ON DELETE SET NULL,
    "Price" numeric(18,2) NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" character varying(256),
    "UpdatedAt" timestamp with time zone,
    "UpdatedBy" character varying(256),
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp with time zone,
    "DeletedBy" text
);

CREATE INDEX IF NOT EXISTS "IX_PosPriceListItems_PriceList_Product"
    ON "PosPriceListItems" ("PriceListId", "ProductId", "VariantId", "UnitId");

ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "PriceListId" uuid NULL;
