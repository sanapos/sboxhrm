-- Đơn giá giờ tăng ca: base | completion | base_plus_completion (mặc định base).
ALTER TABLE "SalaryProfiles"
  ADD COLUMN IF NOT EXISTS "OvertimeHourlyBaseMode" character varying(40) NULL;
