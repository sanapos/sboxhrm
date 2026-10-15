-- Giới hạn riêng từng cửa hàng (số chi nhánh / tài khoản / thiết bị / thông báo) do Super Admin đặt.
ALTER TABLE "Stores" ADD COLUMN IF NOT EXISTS "LimitOverridesJson" text NULL;
