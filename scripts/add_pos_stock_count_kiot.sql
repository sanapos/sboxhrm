-- Kiểm kho KiotViet: giá vốn dòng, ĐVT, người cân bằng

ALTER TABLE "PosStockCountLines" ADD COLUMN IF NOT EXISTS "UnitName" character varying(100);
ALTER TABLE "PosStockCountLines" ADD COLUMN IF NOT EXISTS "CostPrice" numeric(18,2) NOT NULL DEFAULT 0;

ALTER TABLE "PosStockCounts" ADD COLUMN IF NOT EXISTS "BalancedBy" character varying(256);
