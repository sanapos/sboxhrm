-- Bán offline / lịch sử cài app / số liệu mạng: cột ngày giờ tạo nhầm kiểu "timestamp with time zone"
-- trong khi mô hình EF (và mọi bảng khác) dùng "timestamp without time zone" → giá trị UTC ứng dụng ghi vào
-- bị PostgreSQL hiểu theo múi giờ phiên (Asia/Bangkok) → lưu lệch 7 giờ (báo cáo «Bán offline» hiện giờ bán
-- sớm 7 giờ, lọc theo ngày lệch). Đổi về "timestamp without time zone", khôi phục đúng con số đã ghi bằng
-- chính múi giờ phiên. Chạy nhiều lần an toàn: chỉ đổi cột còn là timestamptz.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND data_type = 'timestamp with time zone'
      AND ((table_name = 'PosSaleOrders' AND column_name = 'OfflineAt')
        OR table_name IN ('PosDeviceInstalls', 'PosOfflineSerialBlocks', 'PosNetworkSamples'))
  LOOP
    EXECUTE format(
      'ALTER TABLE %I ALTER COLUMN %I TYPE timestamp without time zone USING (%I AT TIME ZONE current_setting(''TimeZone''))',
      r.table_name, r.column_name, r.column_name);
  END LOOP;
END $$;
