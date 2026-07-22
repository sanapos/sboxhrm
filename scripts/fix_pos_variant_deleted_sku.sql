-- Giải phóng SkuCode trên biến thể đã soft-delete (tránh unique index conflict khi sync)
UPDATE "PosProductVariants"
SET "SkuCode" = LEFT("SkuCode", 40) || '-X' || SUBSTRING(REPLACE("Id"::text, '-', ''), 1, 5)
WHERE "Deleted" IS NOT NULL
  AND "SkuCode" NOT LIKE '%-X%';
