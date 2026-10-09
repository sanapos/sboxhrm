BEGIN;

-- Thông báo: đợt gửi (lịch sử đã gửi / ai đã đọc)
ALTER TABLE "Notifications" ADD COLUMN IF NOT EXISTS "BatchId" uuid NULL;
CREATE INDEX IF NOT EXISTS "IX_Notifications_BatchId" ON "Notifications" ("BatchId") WHERE "BatchId" IS NOT NULL;

COMMIT;
