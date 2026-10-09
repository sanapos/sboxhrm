BEGIN;

-- Kho: seri theo chi nhánh / chuyển kho
ALTER TABLE "PosProductSerials" ADD COLUMN IF NOT EXISTS "BranchId" uuid NULL;
ALTER TABLE "PosProductSerials" ADD COLUMN IF NOT EXISTS "TransferId" uuid NULL;
ALTER TABLE "PosSerialCounts" ADD COLUMN IF NOT EXISTS "BranchId" uuid NULL;
ALTER TABLE "PosStockTransferLines" ADD COLUMN IF NOT EXISTS "SerialNumbersText" text NULL;

COMMIT;
