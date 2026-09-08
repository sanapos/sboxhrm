-- Tăng ca ngày nghỉ chỉ tính giờ OT, không cộng công
ALTER TABLE "SalaryProfiles"
  ADD COLUMN IF NOT EXISTS "RestDayOtHoursOnly" boolean NOT NULL DEFAULT false;
