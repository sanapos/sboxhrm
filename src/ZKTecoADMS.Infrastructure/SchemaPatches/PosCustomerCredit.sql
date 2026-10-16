-- Công nợ khách: hạn mức nợ / hạn thanh toán riêng từng khách (mặc định cửa hàng nằm ở ExtraJson.debt).
ALTER TABLE "PosCustomers" ADD COLUMN IF NOT EXISTS "DebtLimit" numeric(18,2) NULL;
ALTER TABLE "PosCustomers" ADD COLUMN IF NOT EXISTS "PaymentTermDays" integer NULL;
