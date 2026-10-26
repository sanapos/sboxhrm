-- Quét lệnh in treo mỗi phút (PosPrintJobSweepBackgroundService): tìm cửa hàng còn lệnh đang chạy trên MỌI cửa hàng.
-- Chỉ mục (StoreId, Status, …) không dùng được khi không lọc cửa hàng → quét cả bảng lệnh in (30 ngày, mọi cửa hàng)
-- mỗi phút. Chỉ mục riêng phần lệnh đang chạy: chỉ vài dòng, quét chỉ mục là xong.
-- Status: 0 Queued, 1 Claimed, 2 Printing (PosPrintJobStatus).
CREATE INDEX IF NOT EXISTS "IX_PosPrintJobs_Active_StoreId"
    ON "PosPrintJobs" ("StoreId") WHERE "Deleted" IS NULL AND "Status" IN (0, 1, 2);
