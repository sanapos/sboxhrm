-- Tùy chọn: tính đi trễ/về sớm khi tăng ca ngày nghỉ (SalaryProfiles)
ALTER TABLE "SalaryProfiles"
  ADD COLUMN IF NOT EXISTS "ApplyLateEarlyOnRestDayOt" boolean NOT NULL DEFAULT true;
