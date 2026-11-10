-- PenaltyTickets.ShiftId lưu id CA MẪU (ShiftTemplates — WorkSchedules.ShiftId), không phải bảng Shifts cũ.
-- Migration AddPenaltyTickets tạo FK PenaltyTickets→Shifts → mọi phiếu phạt tự động của nhân viên ĐÃ XẾP CA
-- lỗi 23503 và bị bỏ qua âm thầm (chỉ phiếu không gắn ca mới lưu được). Bỏ FK như LeaveShiftFkDrop.sql.
ALTER TABLE "PenaltyTickets" DROP CONSTRAINT IF EXISTS "FK_PenaltyTickets_Shifts_ShiftId";

CREATE INDEX IF NOT EXISTS "IX_PenaltyTickets_ShiftId" ON "PenaltyTickets" ("ShiftId");
