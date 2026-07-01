-- VAT từng dòng phiếu nhập + giảm giá phiếu theo % hoặc giá trị

ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "VatRate" numeric(5,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "VatAmount" numeric(18,2) NOT NULL DEFAULT 0;

ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "DiscountIsPercent" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "DiscountInput" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "TotalVat" numeric(18,2) NOT NULL DEFAULT 0;
