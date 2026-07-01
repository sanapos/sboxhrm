-- Thẻ kho / phiếu nhập: gắn biến thể (ĐVT / hàng cùng loại)
ALTER TABLE "PosStockTransactions" ADD COLUMN IF NOT EXISTS "VariantId" uuid NULL;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "VariantId" uuid NULL;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosStockTransactions_Variant') THEN
        ALTER TABLE "PosStockTransactions"
            ADD CONSTRAINT "FK_PosStockTransactions_Variant"
            FOREIGN KEY ("VariantId") REFERENCES "PosProductVariants"("Id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosStockReceiptLines_Variant') THEN
        ALTER TABLE "PosStockReceiptLines"
            ADD CONSTRAINT "FK_PosStockReceiptLines_Variant"
            FOREIGN KEY ("VariantId") REFERENCES "PosProductVariants"("Id") ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_VariantId" ON "PosStockTransactions"("VariantId");
