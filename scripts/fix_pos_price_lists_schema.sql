-- Bổ sung cột AuditableEntity thiếu (script add_pos_price_lists.sql cũ không đủ)
ALTER TABLE "PosPriceLists" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone;
ALTER TABLE "PosPriceLists" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text;
ALTER TABLE "PosPriceLists" ADD COLUMN IF NOT EXISTS "DeletedBy" text;

ALTER TABLE "PosPriceListItems" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone;
ALTER TABLE "PosPriceListItems" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text;
ALTER TABLE "PosPriceListItems" ADD COLUMN IF NOT EXISTS "DeletedBy" text;

-- FK đơn bán → bảng giá (tùy chọn, không chặn xóa bảng giá cũ)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosSaleOrders_PriceList') THEN
        ALTER TABLE "PosSaleOrders"
            ADD CONSTRAINT "FK_PosSaleOrders_PriceList"
            FOREIGN KEY ("PriceListId") REFERENCES "PosPriceLists"("Id") ON DELETE SET NULL;
    END IF;
END $$;
