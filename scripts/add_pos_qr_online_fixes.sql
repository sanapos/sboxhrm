BEGIN;

-- QR / đơn online / đặt bàn
ALTER TABLE "PosServiceResources" ADD COLUMN IF NOT EXISTS "BranchId" uuid NULL;
ALTER TABLE "PosStoreSellSettings" ADD COLUMN IF NOT EXISTS "OnlineBranchId" uuid NULL;
ALTER TABLE "PosStoreSellSettings" ADD COLUMN IF NOT EXISTS "OnlineMinOrder" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStoreSellSettings" ADD COLUMN IF NOT EXISTS "OnlineShipFee" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStoreSellSettings" ADD COLUMN IF NOT EXISTS "OnlineFreeShipFrom" numeric(18,2) NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS "PosQrRequestLogs" (
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
    "RequestId" character varying(80) NOT NULL,
    "Token" character varying(80) NULL,
    "ResultJson" text NULL,
    CONSTRAINT "PK_PosQrRequestLogs" PRIMARY KEY ("Id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosQrRequestLogs_StoreId_RequestId" ON "PosQrRequestLogs" ("StoreId", "RequestId");
CREATE INDEX IF NOT EXISTS "IX_PosQrRequestLogs_CreatedAt" ON "PosQrRequestLogs" ("CreatedAt");

COMMIT;
