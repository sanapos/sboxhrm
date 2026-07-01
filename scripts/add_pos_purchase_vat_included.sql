-- VAT đã bao gồm thuế + Không chịu thuế (KCT) trên dòng phiếu nhập

ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "VatIncluded" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosStockReceiptLines" ADD COLUMN IF NOT EXISTS "VatExempt" boolean NOT NULL DEFAULT false;
