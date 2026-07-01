-- P1: Xuất kho, kiểm kê, liên kết thẻ kho
CREATE TABLE IF NOT EXISTS "PosStockIssues" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "IssueNo" character varying(30) NOT NULL DEFAULT '',
    "Reason" character varying(200),
    "Note" character varying(500),
    "TotalQty" numeric(18,4) NOT NULL DEFAULT 0,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "FK_PosStockIssues_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosStockIssues_StoreId_IssueNo" ON "PosStockIssues"("StoreId", "IssueNo");

CREATE TABLE IF NOT EXISTS "PosStockIssueLines" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "IssueId" uuid NOT NULL,
    "ProductId" uuid NOT NULL,
    "VariantId" uuid,
    "ProductName" character varying(500) NOT NULL DEFAULT '',
    "ProductCode" character varying(50),
    "Qty" numeric(18,4) NOT NULL DEFAULT 0,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "FK_PosStockIssueLines_Issue" FOREIGN KEY ("IssueId") REFERENCES "PosStockIssues"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_PosStockIssueLines_Product" FOREIGN KEY ("ProductId") REFERENCES "PosProducts"("Id") ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS "PosStockCounts" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "CountNo" character varying(30) NOT NULL DEFAULT '',
    "Name" character varying(200) NOT NULL DEFAULT '',
    "Note" character varying(500),
    "Status" integer NOT NULL DEFAULT 0,
    "CompletedAt" timestamp without time zone,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "FK_PosStockCounts_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosStockCounts_StoreId_CountNo" ON "PosStockCounts"("StoreId", "CountNo");

CREATE TABLE IF NOT EXISTS "PosStockCountLines" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "CountId" uuid NOT NULL,
    "ProductId" uuid NOT NULL,
    "VariantId" uuid,
    "ProductName" character varying(500) NOT NULL DEFAULT '',
    "ProductCode" character varying(50),
    "SystemQty" numeric(18,4) NOT NULL DEFAULT 0,
    "CountedQty" numeric(18,4),
    "IsChecked" boolean NOT NULL DEFAULT false,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "FK_PosStockCountLines_Count" FOREIGN KEY ("CountId") REFERENCES "PosStockCounts"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_PosStockCountLines_Product" FOREIGN KEY ("ProductId") REFERENCES "PosProducts"("Id") ON DELETE RESTRICT
);

ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "StockIssueId" uuid;
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "StockCountId" uuid;
