-- Hàng gia công (cửa nhôm kính, nội thất…): giá theo m² có tối thiểu mỗi bộ
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "IsMadeToOrder" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "PriceByArea" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "MinPricePerSet" numeric(18,2) NULL;
ALTER TABLE "PosQuoteLines" ADD COLUMN IF NOT EXISTS "PricePerM2" numeric(18,2) NULL;
ALTER TABLE "PosQuoteLines" ADD COLUMN IF NOT EXISTS "AreaM2" numeric(18,4) NULL;
ALTER TABLE "PosQuoteLines" ADD COLUMN IF NOT EXISTS "MinPricePerSet" numeric(18,2) NULL;
-- Hợp đồng: số HĐ + mốc tiến độ
ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "ContractNo" character varying(50) NULL;
ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "ContractSignedAt" timestamp without time zone NULL;
ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "ProductionDueAt" timestamp without time zone NULL;
ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "InstallDueAt" timestamp without time zone NULL;
ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "HandoverDueAt" timestamp without time zone NULL;
ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "ContractNote" character varying(1000) NULL;
-- Đợt thanh toán của hợp đồng
CREATE TABLE IF NOT EXISTS "PosQuotePaymentStages" (
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
    "QuoteId" uuid NOT NULL REFERENCES "PosQuotes" ("Id") ON DELETE CASCADE,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "Title" character varying(200) NOT NULL DEFAULT '',
    "Percent" numeric(5,2) NULL,
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "DueDate" timestamp without time zone NULL,
    "Note" character varying(500) NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosQuotePaymentStages_QuoteId" ON "PosQuotePaymentStages" ("QuoteId");
-- Thu tiền theo hợp đồng (mỗi lần gắn một phiếu thu quỹ)
CREATE TABLE IF NOT EXISTS "PosQuotePayments" (
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
    "QuoteId" uuid NOT NULL REFERENCES "PosQuotes" ("Id") ON DELETE CASCADE,
    "StageId" uuid NULL,
    "CashTransactionId" uuid NULL,
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "PaidAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "PaymentMethod" character varying(50) NULL,
    "BankAccountId" uuid NULL,
    "Note" character varying(500) NULL,
    "CollectedBy" character varying(200) NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosQuotePayments_QuoteId" ON "PosQuotePayments" ("QuoteId");
CREATE INDEX IF NOT EXISTS "IX_PosQuotePayments_Store_PaidAt" ON "PosQuotePayments" ("StoreId", "PaidAt");
