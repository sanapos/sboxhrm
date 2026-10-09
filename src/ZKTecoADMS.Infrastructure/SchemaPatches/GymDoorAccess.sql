-- Hội viên gym: trạng thái thông báo «hết hạn» đã đẩy lên máy ở cửa (chế độ máy chủ mở cửa).
ALTER TABLE "PosGymMemberDevices" ADD COLUMN IF NOT EXISTS "AccessBlocked" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosGymMemberDevices" ADD COLUMN IF NOT EXISTS "AccessSyncedAt" timestamp without time zone NULL;
-- PIN hội viên = số điện thoại: tra theo cửa hàng + PIN (chống trùng PIN giữa 2 khách).
CREATE INDEX IF NOT EXISTS "IX_PosGymMemberDevices_Store_Pin" ON "PosGymMemberDevices" ("StoreId", "Pin");
