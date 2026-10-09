BEGIN;

-- PosProductSerial: sổ seri máy (nhập kho → bán → trả NCC)
CREATE TABLE IF NOT EXISTS "PosProductSerials" (
    "Id" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "ProductId" uuid NOT NULL,
    "VariantId" uuid NULL,
    "SerialNumber" character varying(100) NOT NULL,
    "Imei" character varying(50) NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "ReceiptId" uuid NULL,
    "PurchaseReturnId" uuid NULL,
    "SaleOrderId" uuid NULL,
    "ReceivedDate" timestamp without time zone NOT NULL DEFAULT NOW(),
    "SoldDate" timestamp without time zone NULL,
    "CostPrice" numeric(18,2) NOT NULL DEFAULT 0,
    "Note" character varying(500) NULL,
    CONSTRAINT "PK_PosProductSerials" PRIMARY KEY ("Id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosProductSerials_StoreId_SerialNumber"
    ON "PosProductSerials" ("StoreId", "SerialNumber") WHERE "Deleted" IS NULL AND "Status" IN (0, 1);
CREATE INDEX IF NOT EXISTS "IX_PosProductSerials_StoreId_ProductId_Status" ON "PosProductSerials" ("StoreId", "ProductId", "Status");
CREATE INDEX IF NOT EXISTS "IX_PosProductSerials_ReceiptId" ON "PosProductSerials" ("ReceiptId");
CREATE INDEX IF NOT EXISTS "IX_PosProductSerials_SaleOrderId" ON "PosProductSerials" ("SaleOrderId");
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "SerialNumbersText" text NULL;
ALTER TABLE "PosPurchaseReturnLines" ADD COLUMN IF NOT EXISTS "SerialNumbersText" text NULL;

COMMIT;
