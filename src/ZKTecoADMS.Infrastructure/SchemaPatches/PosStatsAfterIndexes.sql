-- Thống kê cho chỉ mục biểu thức ngày bán (PosSearchAndReportIndexes.sql). Postgres chỉ có thống kê của biểu thức
-- COALESCE("SaleDate","CreatedAt") sau một lần ANALYZE bảng — tự ANALYZE chỉ chạy khi bảng đổi ~10% nên cửa hàng lớn có
-- thể chờ nhiều ngày. Thiếu thống kê, kỳ 1 năm bị ước 1.000 đơn thay vì 100.000 → chọn vòng lặp lồng theo từng đơn
-- (báo cáo dài chậm gấp 2–3 lần). Chỉ ANALYZE khi chưa có thống kê (một lần sau khi tạo chỉ mục), không chạy mỗi lần khởi động.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'IX_PosSaleOrders_Store_SaleDay')
       AND NOT EXISTS (SELECT 1 FROM pg_stats WHERE tablename = 'IX_PosSaleOrders_Store_SaleDay') THEN
        ANALYZE "PosSaleOrders";
    END IF;
END $$;
