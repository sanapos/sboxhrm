ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "LunchBreakStartTime" interval;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "LunchBreakEndTime" interval;
SELECT column_name FROM information_schema.columns
WHERE table_name = 'ShiftTemplates'
  AND column_name IN ('LunchBreakStartTime', 'LunchBreakEndTime')
ORDER BY 1;
