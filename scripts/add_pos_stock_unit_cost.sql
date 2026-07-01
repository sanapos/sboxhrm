-- Giá vốn / giá trị tiền trên thẻ kho POS
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "UnitCost" numeric(18,4) NULL;
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "LineAmount" numeric(18,2) NULL;
