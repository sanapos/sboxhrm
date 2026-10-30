-- Mã phiếu phạt (PP-yyyyMMdd-0001) đánh số riêng từng cửa hàng nhưng index cũ bắt duy nhất TOÀN HỆ THỐNG
-- → cửa hàng thứ hai tạo phiếu phạt cùng ngày (tay hoặc tự sinh từ chấm công) lỗi trùng khóa 500.
-- Đổi sang duy nhất theo (StoreId, TicketCode) trong các phiếu chưa xóa. Chạy lại mỗi lần khởi động không tốn.
DO $$
BEGIN
  IF to_regclass('"PenaltyTickets"') IS NULL THEN RETURN; END IF;
  DROP INDEX IF EXISTS "IX_PenaltyTickets_TicketCode";
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'IX_PenaltyTickets_StoreId_TicketCode') THEN
    CREATE UNIQUE INDEX "IX_PenaltyTickets_StoreId_TicketCode"
      ON "PenaltyTickets" ("StoreId", "TicketCode") WHERE "Deleted" IS NULL;
  END IF;
END $$;
