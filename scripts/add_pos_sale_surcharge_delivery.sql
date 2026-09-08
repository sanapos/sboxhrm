ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "SurchargeAmount" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryFee" numeric(18,2) NOT NULL DEFAULT 0;
SELECT column_name FROM information_schema.columns
 WHERE table_name = 'PosSaleOrders'
   AND column_name IN ('SurchargeAmount','DeliveryFee')
 ORDER BY 1;
