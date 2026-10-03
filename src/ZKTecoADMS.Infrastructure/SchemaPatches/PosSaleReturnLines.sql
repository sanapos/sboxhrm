-- Chi tiết phiếu trả hàng bán theo dòng hóa đơn gốc (đã trả bao nhiêu, tiền hoàn, giá vốn hoàn)
CREATE TABLE IF NOT EXISTS "PosSaleReturnLines" (
    "Id" uuid NOT NULL PRIMARY KEY,
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
    "SaleOrderId" uuid NOT NULL,
    "SaleOrderLineId" uuid NOT NULL,
    "ReturnNo" character varying(50) NOT NULL DEFAULT '',
    "ProductId" uuid NOT NULL,
    "VariantId" uuid NULL,
    "Qty" numeric(18,4) NOT NULL DEFAULT 0,
    "RefundAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "CostAmount" numeric(18,4) NOT NULL DEFAULT 0,
    "IsVoided" boolean NOT NULL DEFAULT false,
    "VoidedAt" timestamp without time zone NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosSaleReturnLines_Order" ON "PosSaleReturnLines" ("SaleOrderId");
CREATE INDEX IF NOT EXISTS "IX_PosSaleReturnLines_Store_Created" ON "PosSaleReturnLines" ("StoreId", "CreatedAt");
CREATE INDEX IF NOT EXISTS "IX_PosSaleReturnLines_ReturnNo" ON "PosSaleReturnLines" ("StoreId", "ReturnNo");
