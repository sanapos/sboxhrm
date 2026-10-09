BEGIN;

-- Lô/HSD theo chi nhánh
ALTER TABLE "PosStockLots" ADD COLUMN IF NOT EXISTS "BranchId" uuid NULL;
CREATE INDEX IF NOT EXISTS "IX_PosStockLots_StoreId_BranchId" ON "PosStockLots" ("StoreId", "BranchId");
ALTER TABLE "PosStockTransferLines" ADD COLUMN IF NOT EXISTS "LotAllocJson" text NULL;

COMMIT;
