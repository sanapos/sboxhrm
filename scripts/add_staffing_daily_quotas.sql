-- Định mức nhân sự theo từng thứ (T2–CN) cho mỗi ca + phòng ban
ALTER TABLE "ShiftStaffingQuotas"
    ADD COLUMN IF NOT EXISTS "DailyQuotasJson" text NULL;
