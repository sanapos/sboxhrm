-- Add OvernightCutoffTime column to ShiftTemplates
-- This column stores the cutoff time for overnight shifts (e.g., 07:00 for a 22:00-06:00 shift)
-- The cutoff defines the end boundary for "today's" attendance report.

ALTER TABLE "ShiftTemplates"
  ADD COLUMN IF NOT EXISTS "OvernightCutoffTime" interval NULL;

COMMENT ON COLUMN "ShiftTemplates"."OvernightCutoffTime"
  IS 'Giờ qua đêm: mốc thời gian kết thúc ca đêm. Bắt buộc khi ShiftType = Qua đêm. Ví dụ: ca 22:00-06:00 thì OvernightCutoffTime = 07:30';
