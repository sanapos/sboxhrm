-- Unify work-day boundary: AppSettings.day_end_time only.
-- Migrate OvernightCutoffTime from overnight shifts into day_end_time when needed,
-- then drop ShiftTemplates.OvernightCutoffTime.

BEGIN;

-- 1) UPDATE existing midnight day_end_time from active overnight shift cutoff
UPDATE "AppSettings" a
SET "Value" = to_char(st."OvernightCutoffTime", 'HH24:MI:SS'),
    "Description" = COALESCE(NULLIF(a."Description", ''), 'Giờ kết thúc ngày làm việc')
FROM (
    SELECT DISTINCT ON ("StoreId") "StoreId", "OvernightCutoffTime"
    FROM "ShiftTemplates"
    WHERE "IsActive" = true
      AND "OvernightCutoffTime" IS NOT NULL
      AND (
          "ShiftType" ILIKE '%quadem%'
          OR "ShiftType" = 'Qua đêm'
          OR "ShiftType" = 'QuaDem'
      )
      AND "StoreId" IS NOT NULL
    ORDER BY "StoreId", "UpdatedAt" DESC NULLS LAST, "CreatedAt" DESC
) st
WHERE a."StoreId" = st."StoreId"
  AND a."Key" = 'day_end_time'
  AND (a."Value" IS NULL OR a."Value" IN ('00:00:00', '0:00:00', '00:00', '0:00'));

-- 2) INSERT day_end_time for stores that have overnight cutoff but no setting yet
INSERT INTO "AppSettings" (
    "Id", "Key", "Value", "Description", "Group", "DataType", "DisplayOrder",
    "IsPublic", "CreatedAt", "IsActive", "StoreId"
)
SELECT
    gen_random_uuid(),
    'day_end_time',
    to_char(st."OvernightCutoffTime", 'HH24:MI:SS'),
    'Giờ kết thúc ngày làm việc (đồng bộ từ ca đêm cũ)',
    'General',
    'text',
    0,
    true,
    NOW(),
    true,
    st."StoreId"
FROM (
    SELECT DISTINCT ON ("StoreId") "StoreId", "OvernightCutoffTime"
    FROM "ShiftTemplates"
    WHERE "IsActive" = true
      AND "OvernightCutoffTime" IS NOT NULL
      AND (
          "ShiftType" ILIKE '%quadem%'
          OR "ShiftType" = 'Qua đêm'
          OR "ShiftType" = 'QuaDem'
      )
      AND "StoreId" IS NOT NULL
    ORDER BY "StoreId", "UpdatedAt" DESC NULLS LAST, "CreatedAt" DESC
) st
WHERE NOT EXISTS (
    SELECT 1 FROM "AppSettings" a
    WHERE a."StoreId" = st."StoreId" AND a."Key" = 'day_end_time'
);

ALTER TABLE "ShiftTemplates" DROP COLUMN IF EXISTS "OvernightCutoffTime";

COMMIT;
