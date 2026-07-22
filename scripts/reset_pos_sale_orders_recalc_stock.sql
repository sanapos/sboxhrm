-- Xóa mềm toàn bộ đơn bán POS + vô hiệu biến động kho từ bán hàng, tính lại tồn.
-- Chạy trên production: scripts/deploy-pos-sales-reset.ps1

BEGIN;

-- 1) Xóa mềm tất cả đơn bán
UPDATE "PosSaleOrders"
SET "Deleted" = NOW(), "UpdatedAt" = NOW()
WHERE "Deleted" IS NULL;

-- 2) Vô hiệu mọi biến động kho gắn đơn bán (Sale + Return hủy đơn…)
UPDATE "PosStockTransactions"
SET "IsActive" = false,
    "Deleted" = NOW(),
    "UpdatedAt" = NOW()
WHERE "SaleOrderId" IS NOT NULL
  AND "Deleted" IS NULL;

-- 3) Tính lại tồn biến thể (có VariantId)
UPDATE "PosProductVariants" v
SET "OnHandQty" = COALESCE(src.qty, 0),
    "UpdatedAt" = NOW()
FROM (
    SELECT t."VariantId", SUM(t."QtyChange") AS qty
    FROM "PosStockTransactions" t
    WHERE t."VariantId" IS NOT NULL
      AND t."Deleted" IS NULL
      AND t."IsActive" = true
    GROUP BY t."VariantId"
) src
WHERE v."Id" = src."VariantId"
  AND v."Deleted" IS NULL;

UPDATE "PosProductVariants" v
SET "OnHandQty" = 0,
    "UpdatedAt" = NOW()
WHERE v."Deleted" IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM "PosStockTransactions" t
      WHERE t."VariantId" = v."Id"
        AND t."Deleted" IS NULL
        AND t."IsActive" = true
  );

-- 4) Tính lại tồn hàng hóa = tổng mọi biến động active theo ProductId
UPDATE "PosProducts" p
SET "OnHandQty" = GREATEST(0, COALESCE(src.qty, 0)),
    "UpdatedAt" = NOW()
FROM (
    SELECT t."ProductId", t."StoreId", SUM(t."QtyChange") AS qty
    FROM "PosStockTransactions" t
    WHERE t."Deleted" IS NULL
      AND t."IsActive" = true
    GROUP BY t."ProductId", t."StoreId"
) src
WHERE p."Id" = src."ProductId"
  AND p."StoreId" = src."StoreId"
  AND p."Deleted" IS NULL;

UPDATE "PosProducts" p
SET "OnHandQty" = 0,
    "UpdatedAt" = NOW()
WHERE p."Deleted" IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM "PosStockTransactions" t
      WHERE t."ProductId" = p."Id"
        AND t."StoreId" = p."StoreId"
        AND t."Deleted" IS NULL
        AND t."IsActive" = true
  );

COMMIT;

-- Thống kê sau reset
SELECT 'PosSaleOrders active' AS label, COUNT(*)::text AS val
FROM "PosSaleOrders" WHERE "Deleted" IS NULL
UNION ALL
SELECT 'Sale stock txs active', COUNT(*)::text
FROM "PosStockTransactions"
WHERE "SaleOrderId" IS NOT NULL AND "Deleted" IS NULL AND "IsActive" = true
UNION ALL
SELECT 'Products sample stock', string_agg("Name" || '=' || "OnHandQty"::text, ', ' ORDER BY "Name")
FROM (SELECT "Name", "OnHandQty" FROM "PosProducts" WHERE "Deleted" IS NULL ORDER BY "Name" LIMIT 8) s;
