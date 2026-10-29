-- Leaves.ShiftId lưu id CA MẪU (ShiftTemplates), không phải Shifts. Điều hướng Shift.Leave làm EF coi là quan hệ
-- 1-1 → migration AddPenaltyTickets thêm nhầm FK Leaves→Shifts (mọi đơn nghỉ mới lỗi 23503) và chỉ mục
-- IX_Leaves_ShiftId UNIQUE (mỗi ca mẫu chỉ được một đơn). Bỏ FK, đổi chỉ mục về thường.
ALTER TABLE "Leaves" DROP CONSTRAINT IF EXISTS "FK_Leaves_Shifts_ShiftId";

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_indexes
             WHERE tablename = 'Leaves' AND indexname = 'IX_Leaves_ShiftId'
               AND indexdef LIKE 'CREATE UNIQUE%') THEN
    DROP INDEX "IX_Leaves_ShiftId";
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS "IX_Leaves_ShiftId" ON "Leaves" ("ShiftId");
