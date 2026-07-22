-- Tính lại tồn kho từ biến động active (sau nhập/bán/hủy).
BEGIN;

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
      SELECT 1 FROM "PosStockTransactions" t
      WHERE t."VariantId" = v."Id"
        AND t."Deleted" IS NULL
        AND t."IsActive" = true
  );

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
      SELECT 1 FROM "PosStockTransactions" t
      WHERE t."ProductId" = p."Id"
        AND t."StoreId" = p."StoreId"
        AND t."Deleted" IS NULL
        AND t."IsActive" = true
  );

COMMIT;

SELECT "Name", "OnHandQty"
FROM "PosProducts"
WHERE "Deleted" IS NULL
  AND "Name" ILIKE '%phộng%'
ORDER BY "Name";
