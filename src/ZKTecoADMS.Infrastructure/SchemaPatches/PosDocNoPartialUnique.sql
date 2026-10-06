-- Mã chứng từ chỉ cần duy nhất trong các bản ghi CHƯA XÓA (giống IX_PosSaleOrders_StoreId_OrderNo).
-- Trước đây xóa phiếu nháp (xóa mềm) giữ lại mã; bộ sinh mã bỏ qua bản ghi đã xóa → sinh lại đúng mã đó
-- → lỗi trùng khóa, không tạo được phiếu xuất hủy / dùng nội bộ / kiểm kho / trả NCC / khách / NCC mới.
-- Chỉ dựng lại index khi còn là bản cũ (không có WHERE) — chạy lại mỗi lần khởi động không tốn.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('PosStockIssues', 'IX_PosStockIssues_StoreId_IssueNo', 'IssueNo'),
      ('PosStockCounts', 'IX_PosStockCounts_StoreId_CountNo', 'CountNo'),
      ('PosPurchaseReturns', 'IX_PosPurchaseReturns_StoreId_ReturnNo', 'ReturnNo'),
      ('PosCustomers', 'IX_PosCustomers_StoreId_CustomerCode', 'CustomerCode'),
      ('PosSuppliers', 'IX_PosSuppliers_StoreId_SupplierCode', 'SupplierCode')
    ) AS t(tbl, idx, col)
  LOOP
    IF to_regclass(format('%I', r.tbl)) IS NULL THEN CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = r.idx AND indexdef ILIKE '%WHERE%') THEN CONTINUE; END IF;
    EXECUTE format('DROP INDEX IF EXISTS %I', r.idx);
    EXECUTE format('CREATE UNIQUE INDEX %I ON %I ("StoreId", %I) WHERE "Deleted" IS NULL', r.idx, r.tbl, r.col);
  END LOOP;
END $$;
