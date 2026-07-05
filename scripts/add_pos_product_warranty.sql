-- Bảo hành POS: cấu hình sản phẩm + đăng ký seri máy theo đơn bán
BEGIN;

ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "WarrantyMonths" integer NULL;

ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "RequiresSerial" boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS "PosProductWarrantyRegistrations" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "SaleOrderId" uuid NOT NULL REFERENCES "PosSaleOrders"("Id") ON DELETE CASCADE,
    "SaleOrderLineId" uuid NOT NULL REFERENCES "PosSaleOrderLines"("Id") ON DELETE CASCADE,
    "ProductId" uuid NOT NULL REFERENCES "PosProducts"("Id") ON DELETE RESTRICT,
    "VariantId" uuid NULL REFERENCES "PosProductVariants"("Id") ON DELETE SET NULL,
    "CustomerId" uuid NULL REFERENCES "PosCustomers"("Id") ON DELETE SET NULL,
    "SerialNumber" character varying(100) NOT NULL,
    "Imei" character varying(50) NULL,
    "WarrantyMonths" integer NOT NULL DEFAULT 0,
    "SaleDate" timestamp without time zone NOT NULL,
    "WarrantyExpiry" timestamp without time zone NOT NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "Note" character varying(500) NULL,
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

CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosProductWarrantyRegistrations_StoreId_SerialNumber"
    ON "PosProductWarrantyRegistrations" ("StoreId", "SerialNumber")
    WHERE "Deleted" IS NULL AND "Status" = 0;

CREATE INDEX IF NOT EXISTS "IX_PosProductWarrantyRegistrations_StoreId_SaleOrderId"
    ON "PosProductWarrantyRegistrations" ("StoreId", "SaleOrderId");

CREATE INDEX IF NOT EXISTS "IX_PosProductWarrantyRegistrations_StoreId_ProductId"
    ON "PosProductWarrantyRegistrations" ("StoreId", "ProductId");

CREATE INDEX IF NOT EXISTS "IX_PosProductWarrantyRegistrations_StoreId_WarrantyExpiry"
    ON "PosProductWarrantyRegistrations" ("StoreId", "WarrantyExpiry")
    WHERE "Deleted" IS NULL AND "Status" = 0;

COMMIT;
