-- Quản lý lô / HSD POS (P0): cấu hình sản phẩm, lô kho, phiếu nhập
BEGIN;

ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "TrackExpiry" boolean NOT NULL DEFAULT false;

ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "ExpiryWarningDays" integer NOT NULL DEFAULT 30;

ALTER TABLE "PosStockReceiptLines"
    ADD COLUMN IF NOT EXISTS "LotNo" character varying(50) NULL;

ALTER TABLE "PosStockReceiptLines"
    ADD COLUMN IF NOT EXISTS "ManufactureDate" timestamp without time zone NULL;

ALTER TABLE "PosStockReceiptLines"
    ADD COLUMN IF NOT EXISTS "ExpiryDate" timestamp without time zone NULL;

ALTER TABLE "PosStockTransactions"
    ADD COLUMN IF NOT EXISTS "LotId" uuid NULL;

CREATE TABLE IF NOT EXISTS "PosStockLots" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "ProductId" uuid NOT NULL REFERENCES "PosProducts"("Id") ON DELETE RESTRICT,
    "VariantId" uuid NULL REFERENCES "PosProductVariants"("Id") ON DELETE SET NULL,
    "LotNo" character varying(50) NULL,
    "ManufactureDate" timestamp without time zone NULL,
    "ExpiryDate" timestamp without time zone NULL,
    "QtyOnHand" numeric(18,4) NOT NULL DEFAULT 0,
    "UnitCost" numeric(18,4) NOT NULL DEFAULT 0,
    "Status" integer NOT NULL DEFAULT 0,
    "StockReceiptId" uuid NULL REFERENCES "PosStockReceipts"("Id") ON DELETE SET NULL,
    "StockReceiptLineId" uuid NULL REFERENCES "PosStockReceiptLines"("Id") ON DELETE SET NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

CREATE INDEX IF NOT EXISTS "IX_PosStockLots_StoreId_ProductId_Status"
    ON "PosStockLots" ("StoreId", "ProductId", "Status");

CREATE INDEX IF NOT EXISTS "IX_PosStockLots_StoreId_ExpiryDate"
    ON "PosStockLots" ("StoreId", "ExpiryDate")
    WHERE "Deleted" IS NULL AND "Status" = 0;

CREATE INDEX IF NOT EXISTS "IX_PosStockLots_StockReceiptLineId"
    ON "PosStockLots" ("StockReceiptLineId");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosStockTransactions_PosStockLots_LotId'
    ) THEN
        ALTER TABLE "PosStockTransactions"
            ADD CONSTRAINT "FK_PosStockTransactions_PosStockLots_LotId"
            FOREIGN KEY ("LotId") REFERENCES "PosStockLots"("Id") ON DELETE SET NULL;
    END IF;
END $$;

COMMIT;
