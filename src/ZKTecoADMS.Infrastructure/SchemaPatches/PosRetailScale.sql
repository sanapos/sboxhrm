-- Siêu thị: PLU tem cân + số ngày dùng sau đóng gói (in HSD trên tem cân tại quầy)
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "ScalePlu" character varying(10) NULL;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "PackShelfLifeDays" integer NULL;
CREATE INDEX IF NOT EXISTS "IX_PosProducts_Store_ScalePlu" ON "PosProducts" ("StoreId", "ScalePlu") WHERE "ScalePlu" IS NOT NULL;
