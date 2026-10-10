-- Báo giá theo bảng giá (Thiết lập › Bảng giá)
ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "PriceListId" uuid NULL;
ALTER TABLE "PosQuotes" ADD COLUMN IF NOT EXISTS "PriceListName" character varying(200) NULL;
