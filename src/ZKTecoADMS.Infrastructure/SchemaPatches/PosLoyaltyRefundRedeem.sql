-- Trả hàng có hoàn lại điểm khách đã đổi trên đơn (theo tỷ lệ hàng trả) hay không. Mặc định giữ như cũ: không hoàn.
ALTER TABLE "PosStoreSellSettings" ADD COLUMN IF NOT EXISTS "LoyaltyRefundRedeemOnReturn" boolean NOT NULL DEFAULT false;
