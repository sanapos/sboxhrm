-- Hạng thành viên khách (JSON: [{name, minSpend, color, benefit}]) — hạng tính theo tổng mua của khách.
ALTER TABLE "PosStoreSellSettings" ADD COLUMN IF NOT EXISTS "LoyaltyTiersJson" text NULL;
