-- Thêm cột AutoApproveHoursAfterShift vào PenaltySettings.
-- Mặc định 2 giờ sau kết ca sẽ tự duyệt phiếu phạt nếu NV chưa khiếu nại.
-- 0 = tắt tự duyệt (chờ quản lý duyệt thủ công).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "__SchemaPatches" WHERE "Name" = 'PenaltySettingAutoApproveHours'
  ) THEN
    ALTER TABLE "PenaltySettings"
    ADD COLUMN IF NOT EXISTS "AutoApproveHoursAfterShift" INTEGER NOT NULL DEFAULT 2;

    INSERT INTO "__SchemaPatches" ("Name", "AppliedAt")
    VALUES ('PenaltySettingAutoApproveHours', NOW());
  END IF;
END $$;
