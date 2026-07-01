-- Module Mua hàng kiểu KiotViet: NCC, phiếu nhập PN, trả NCC, thanh toán

CREATE TABLE IF NOT EXISTS "PosSupplierGroups" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "Name" character varying(100) NOT NULL DEFAULT '',
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "FK_PosSupplierGroups_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_PosSupplierGroups_StoreId_Name" ON "PosSupplierGroups"("StoreId", "Name");

ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "SupplierCode" character varying(30) NOT NULL DEFAULT '';
ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "Province" character varying(100);
ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "Ward" character varying(100);
ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "GroupId" uuid;
ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "CompanyName" character varying(200);
ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "TaxCode" character varying(50);
ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "IdentityNo" character varying(50);
ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "Note" character varying(1000);
ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "TotalPurchase" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosSuppliers" ADD COLUMN IF NOT EXISTS "CurrentDebt" numeric(18,2) NOT NULL DEFAULT 0;

-- Backfill mã NCC cho bản ghi cũ
DO $$
DECLARE r RECORD; n INT := 0;
BEGIN
  FOR r IN SELECT "Id" FROM "PosSuppliers" WHERE "SupplierCode" = '' OR "SupplierCode" IS NULL ORDER BY "CreatedAt"
  LOOP
    n := n + 1;
    UPDATE "PosSuppliers" SET "SupplierCode" = 'NCC' || LPAD(n::text, 4, '0') WHERE "Id" = r."Id";
  END LOOP;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosSuppliers_StoreId_SupplierCode"
  ON "PosSuppliers"("StoreId", "SupplierCode") WHERE "Deleted" IS NULL;

ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "Status" integer NOT NULL DEFAULT 1;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "ImportDate" timestamp without time zone;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "ImportedBy" character varying(200);
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "InputInvoiceNo" character varying(50);
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "PurchaseOrderNo" character varying(50);
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "PaidAmount" numeric(18,2) NOT NULL DEFAULT 0;

ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "UnitName" character varying(100);
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "LineNote" character varying(500);

CREATE TABLE IF NOT EXISTS "PosPurchaseReturns" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "ReturnNo" character varying(30) NOT NULL DEFAULT '',
    "SupplierId" uuid,
    "SourceReceiptId" uuid,
    "Note" character varying(500),
    "Status" integer NOT NULL DEFAULT 0,
    "TotalQty" numeric(18,4) NOT NULL DEFAULT 0,
    "TotalAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "RefundDue" numeric(18,2) NOT NULL DEFAULT 0,
    "RefundReceived" numeric(18,2) NOT NULL DEFAULT 0,
    "ReturnDate" timestamp without time zone,
    "ReturnedBy" character varying(200),
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "FK_PosPurchaseReturns_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_PosPurchaseReturns_Supplier" FOREIGN KEY ("SupplierId") REFERENCES "PosSuppliers"("Id") ON DELETE SET NULL,
    CONSTRAINT "FK_PosPurchaseReturns_Receipt" FOREIGN KEY ("SourceReceiptId") REFERENCES "PosStockReceipts"("Id") ON DELETE SET NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosPurchaseReturns_StoreId_ReturnNo" ON "PosPurchaseReturns"("StoreId", "ReturnNo");

CREATE TABLE IF NOT EXISTS "PosPurchaseReturnLines" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "ReturnId" uuid NOT NULL,
    "ProductId" uuid NOT NULL,
    "VariantId" uuid,
    "ProductName" character varying(500) NOT NULL DEFAULT '',
    "ProductCode" character varying(50),
    "UnitName" character varying(100),
    "Qty" numeric(18,4) NOT NULL DEFAULT 0,
    "CostPrice" numeric(18,2) NOT NULL DEFAULT 0,
    "DiscountAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "LineTotal" numeric(18,2) NOT NULL DEFAULT 0,
    "LineNote" character varying(500),
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "FK_PosPurchaseReturnLines_Return" FOREIGN KEY ("ReturnId") REFERENCES "PosPurchaseReturns"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_PosPurchaseReturnLines_Product" FOREIGN KEY ("ProductId") REFERENCES "PosProducts"("Id") ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS "PosSupplierPayments" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "SupplierId" uuid NOT NULL,
    "StockReceiptId" uuid,
    "PaymentNo" character varying(30) NOT NULL DEFAULT '',
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "PaymentMethod" character varying(50) NOT NULL DEFAULT 'Tiền mặt',
    "PaidAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "Note" character varying(500),
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "FK_PosSupplierPayments_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_PosSupplierPayments_Supplier" FOREIGN KEY ("SupplierId") REFERENCES "PosSuppliers"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_PosSupplierPayments_Receipt" FOREIGN KEY ("StockReceiptId") REFERENCES "PosStockReceipts"("Id") ON DELETE SET NULL
);

ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "PurchaseReturnId" uuid;
