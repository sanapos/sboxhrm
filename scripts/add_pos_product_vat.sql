-- Thuế VAT theo từng hàng hóa POS
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "VatRate" numeric(5,2) NOT NULL DEFAULT 8;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "VatExempt" boolean NOT NULL DEFAULT false;
