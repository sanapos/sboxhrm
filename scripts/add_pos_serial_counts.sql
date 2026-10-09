BEGIN;

-- Kiểm kho theo mã (seri / RFID)
ALTER TABLE "PosProductSerials" ADD COLUMN IF NOT EXISTS "TagCode" character varying(100) NULL;
CREATE INDEX IF NOT EXISTS "IX_PosProductSerials_StoreId_TagCode" ON "PosProductSerials" ("StoreId", "TagCode");
CREATE TABLE IF NOT EXISTS "PosSerialCounts" (
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
    "CountNo" character varying(30) NOT NULL,
    "Name" character varying(200) NOT NULL,
    "ProductId" uuid NULL,
    "Source" character varying(20) NOT NULL DEFAULT 'Barcode',
    "Status" integer NOT NULL DEFAULT 0,
    "StartedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CompletedAt" timestamp without time zone NULL,
    "Note" character varying(500) NULL,
    "ExpectedQty" integer NOT NULL DEFAULT 0,
    "MatchedQty" integer NOT NULL DEFAULT 0,
    "MissingQty" integer NOT NULL DEFAULT 0,
    "UnknownQty" integer NOT NULL DEFAULT 0,
    CONSTRAINT "PK_PosSerialCounts" PRIMARY KEY ("Id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosSerialCounts_StoreId_CountNo" ON "PosSerialCounts" ("StoreId", "CountNo");
CREATE TABLE IF NOT EXISTS "PosSerialCountItems" (
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
    "CountId" uuid NOT NULL,
    "Code" character varying(100) NOT NULL,
    "SerialId" uuid NULL,
    "ProductId" uuid NULL,
    "Result" integer NOT NULL DEFAULT 0,
    "ScannedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "DeviceName" character varying(100) NULL,
    CONSTRAINT "PK_PosSerialCountItems" PRIMARY KEY ("Id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosSerialCountItems_CountId_Code" ON "PosSerialCountItems" ("CountId", "Code");
ALTER TABLE "PosStockIssueLines" ADD COLUMN IF NOT EXISTS "SerialNumbersText" text NULL;

COMMIT;
