-- Công nợ KH: thu nợ, tích điểm, voucher POS
BEGIN;

ALTER TABLE "PosCustomers"
    ADD COLUMN IF NOT EXISTS "PointBalance" numeric(18,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS "PosVouchers" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "Code" character varying(50) NOT NULL,
    "Name" character varying(200) NULL,
    "DiscountType" integer NOT NULL DEFAULT 1,
    "DiscountValue" numeric(18,2) NOT NULL DEFAULT 0,
    "MinOrderAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "MaxDiscountAmount" numeric(18,2) NULL,
    "ValidFrom" timestamp without time zone NULL,
    "ValidTo" timestamp without time zone NULL,
    "MaxUses" integer NULL,
    "UsedCount" integer NOT NULL DEFAULT 0,
    "CustomerId" uuid NULL REFERENCES "PosCustomers"("Id") ON DELETE SET NULL,
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

CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosVouchers_StoreId_Code"
    ON "PosVouchers" ("StoreId", "Code") WHERE "Deleted" IS NULL;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "VoucherId" uuid NULL;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "VoucherCode" character varying(50) NULL;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "VoucherDiscount" numeric(18,2) NOT NULL DEFAULT 0;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "PointsRedeemed" numeric(18,2) NOT NULL DEFAULT 0;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "PointsDiscount" numeric(18,2) NOT NULL DEFAULT 0;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "PointsEarned" numeric(18,2) NOT NULL DEFAULT 0;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosSaleOrders_VoucherId'
    ) THEN
        ALTER TABLE "PosSaleOrders"
            ADD CONSTRAINT "FK_PosSaleOrders_VoucherId"
            FOREIGN KEY ("VoucherId") REFERENCES "PosVouchers"("Id") ON DELETE SET NULL;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS "PosCustomerPayments" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "CustomerId" uuid NOT NULL REFERENCES "PosCustomers"("Id") ON DELETE CASCADE,
    "SaleOrderId" uuid NULL REFERENCES "PosSaleOrders"("Id") ON DELETE SET NULL,
    "PaymentNo" character varying(30) NOT NULL,
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "PaymentMethod" character varying(50) NOT NULL DEFAULT 'Tiền mặt',
    "PaidAt" timestamp without time zone NOT NULL,
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

CREATE INDEX IF NOT EXISTS "IX_PosCustomerPayments_StoreId_CustomerId"
    ON "PosCustomerPayments" ("StoreId", "CustomerId");

CREATE TABLE IF NOT EXISTS "PosCustomerPointTransactions" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "CustomerId" uuid NOT NULL REFERENCES "PosCustomers"("Id") ON DELETE CASCADE,
    "SaleOrderId" uuid NULL REFERENCES "PosSaleOrders"("Id") ON DELETE SET NULL,
    "TransactionType" integer NOT NULL DEFAULT 0,
    "Points" numeric(18,2) NOT NULL DEFAULT 0,
    "BalanceAfter" numeric(18,2) NOT NULL DEFAULT 0,
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

CREATE INDEX IF NOT EXISTS "IX_PosCustomerPointTransactions_StoreId_CustomerId"
    ON "PosCustomerPointTransactions" ("StoreId", "CustomerId");

COMMIT;
