-- Slot hóa đơn cố định trên cửa hàng (Draft). Mã HDxxxx chỉ gán khi thanh toán.
BEGIN;

ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "InvoiceSlot" integer NULL;

-- Mỗi cửa hàng: tối đa 1 Draft / slot
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosSaleOrders_StoreId_InvoiceSlot_Draft"
    ON "PosSaleOrders" ("StoreId", "InvoiceSlot")
    WHERE "Deleted" IS NULL AND "Status" = 0 AND "InvoiceSlot" IS NOT NULL;

COMMIT;

SELECT 'add_pos_invoice_slot applied' AS status;
