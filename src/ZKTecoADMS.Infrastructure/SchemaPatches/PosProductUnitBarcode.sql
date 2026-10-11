-- Mã vạch riêng cho đơn vị bán (Thùng / Lốc / Hộp…): quét mã thùng → bán đúng 1 thùng, in tem thùng đúng mã.
ALTER TABLE "PosProductUnits" ADD COLUMN IF NOT EXISTS "Barcode" character varying(64) NULL;

CREATE INDEX IF NOT EXISTS "IX_PosProductUnits_StoreId_Barcode"
    ON "PosProductUnits" ("StoreId", "Barcode")
    WHERE "Barcode" IS NOT NULL AND "Deleted" IS NULL;
