ALTER TABLE "StockTransactions" ADD COLUMN IF NOT EXISTS "CreatedAt" timestamp NOT NULL DEFAULT NOW();
ALTER TABLE "StockTransactions" ADD COLUMN IF NOT EXISTS "UpdatedAt" timestamp;
ALTER TABLE "StockTransactions" ADD COLUMN IF NOT EXISTS "UpdatedBy" text;
ALTER TABLE "StockTransactions" ADD COLUMN IF NOT EXISTS "CreatedBy" text;
