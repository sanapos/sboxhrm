-- Lưu mật khẩu plain text để Super Admin tra cứu (chỉ hiển thị trong System Admin).
ALTER TABLE "AspNetUsers" ADD COLUMN IF NOT EXISTS "PlainTextPassword" text;
