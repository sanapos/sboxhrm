-- Zalo bot: liên kết theo hồ sơ nhân viên (nhân viên không có tài khoản app vẫn nhận lương / phạt / lịch làm qua Zalo).
-- Chạy sau ZaloBot.sql (thứ tự tên file). Mỗi lệnh chạy được nhiều lần.
ALTER TABLE "ZaloBotLinks" ALTER COLUMN "UserId" DROP NOT NULL;
ALTER TABLE "ZaloBotLinks" ADD COLUMN IF NOT EXISTS "EmployeeId" uuid NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "IX_ZaloBotLinks_Store_Employee" ON "ZaloBotLinks" ("StoreId", "EmployeeId") WHERE "EmployeeId" IS NOT NULL;

ALTER TABLE "ZaloBotMessages" ADD COLUMN IF NOT EXISTS "EmployeeId" uuid NULL;
