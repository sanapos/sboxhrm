-- Tích điểm theo % từng sản phẩm (VD hộp thịt 100k, 20% → tích 20.000đ vào ví điểm). NULL = theo mức chung cửa hàng.
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "LoyaltyPercent" numeric(7,2) NULL;
