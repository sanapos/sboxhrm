-- Chiết khấu + ghi chú từng dòng đơn bán hàng POS
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "DiscountAmount" numeric NOT NULL DEFAULT 0;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "LineNote" character varying(500);
