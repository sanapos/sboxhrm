-- Đếm số lần in hóa đơn POS (in lại khi PrintCount > 1)
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "PrintCount" integer NOT NULL DEFAULT 0;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "LastPrintedAt" timestamp without time zone;
