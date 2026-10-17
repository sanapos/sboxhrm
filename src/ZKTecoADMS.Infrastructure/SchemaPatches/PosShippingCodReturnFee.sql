-- Đối soát COD ghi sổ quỹ (số đã ghi) + cước hoàn hàng hãng thu thêm.
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryCodReceivedAmount" numeric(18,2) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryReturnFee" numeric(18,2) NULL;
