-- Tem cân: mỗi PLU chỉ thuộc một hàng (chưa xóa) trong cửa hàng — quét tem ra đúng hàng.
-- Chỉ tạo khi dữ liệu hiện có chưa trùng (trùng cũ: sửa tay ở màn hàng hóa, app đã chặn trùng mới).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "PosProducts"
    WHERE "ScalePlu" IS NOT NULL AND "Deleted" IS NULL
    GROUP BY "StoreId", "ScalePlu" HAVING COUNT(*) > 1
  ) THEN
    CREATE UNIQUE INDEX IF NOT EXISTS "UX_PosProducts_Store_ScalePlu"
      ON "PosProducts" ("StoreId", "ScalePlu")
      WHERE "ScalePlu" IS NOT NULL AND "Deleted" IS NULL;
  END IF;
END $$;
