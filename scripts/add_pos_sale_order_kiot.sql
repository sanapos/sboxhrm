-- Hóa đơn / đơn hàng POS: người bán, kênh, bảng giá, ngày bán
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "SaleDate" timestamp without time zone;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "SoldBy" character varying(200);
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "SalesChannel" character varying(100);
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "PriceListName" character varying(100);

UPDATE "PosSaleOrders"
SET "SaleDate" = "CreatedAt"
WHERE "SaleDate" IS NULL;

UPDATE "PosSaleOrders"
SET "SoldBy" = "CreatedBy"
WHERE "SoldBy" IS NULL AND "CreatedBy" IS NOT NULL;

UPDATE "PosSaleOrders"
SET "SalesChannel" = 'Bán trực tiếp'
WHERE "SalesChannel" IS NULL OR "SalesChannel" = '';

UPDATE "PosSaleOrders"
SET "PriceListName" = 'Bảng giá chung'
WHERE "PriceListName" IS NULL OR "PriceListName" = '';
