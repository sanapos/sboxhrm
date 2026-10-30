-- VAT đầu vào: ngày / ký hiệu hóa đơn mua vào trên phiếu nhập; VAT trên phiếu trả hàng nhà cung cấp.
-- Chạy lại mỗi lần khởi động không tốn (IF NOT EXISTS).
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "InputInvoiceDate" timestamp without time zone NULL;
ALTER TABLE "PosStockReceipts" ADD COLUMN IF NOT EXISTS "InputInvoiceSerial" character varying(20) NULL;
ALTER TABLE "PosPurchaseReturns" ADD COLUMN IF NOT EXISTS "TotalVat" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosPurchaseReturnLines" ADD COLUMN IF NOT EXISTS "VatRate" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosPurchaseReturnLines" ADD COLUMN IF NOT EXISTS "VatAmount" numeric(18,2) NOT NULL DEFAULT 0;
