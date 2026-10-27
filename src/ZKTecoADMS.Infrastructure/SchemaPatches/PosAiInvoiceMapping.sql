-- Chụp hóa đơn NCC → phiếu nhập: nhớ tên hàng trên hóa đơn (theo cửa hàng + NCC) ứng với hàng của cửa hàng
CREATE TABLE IF NOT EXISTS "PosAiInvoiceMappings" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "SupplierId" uuid NULL,
    "NameKey" character varying(300) NOT NULL DEFAULT '',
    "InvoiceName" character varying(500) NOT NULL DEFAULT '',
    "ProductId" uuid NOT NULL,
    "InvoiceUnit" character varying(100) NULL,
    "UnitName" character varying(100) NULL,
    "UnitFactor" numeric NOT NULL DEFAULT 1,
    "UseCount" integer NOT NULL DEFAULT 0,
    "LastUsedAt" timestamp without time zone NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS "IX_PosAiInvoiceMappings_Store_Supplier_Key" ON "PosAiInvoiceMappings" ("StoreId", "SupplierId", "NameKey");
