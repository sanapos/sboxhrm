-- Chỉ mục tìm kiếm không dấu (VnSearch.Has → translate(lower(x),…) LIKE '%…%').
-- Chạy một lần, nên chạy ngoài giờ cao điểm trên bảng lớn (CREATE INDEX khóa ghi trong lúc tạo).
-- Cần quyền tạo extension pg_trgm; thiếu quyền thì script bỏ qua, tìm kiếm vẫn chạy (chậm hơn).
DO $$
DECLARE
  f text := 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ̛̣̀́̃̉̂̆';
  t text := 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydaaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  r record;
BEGIN
  BEGIN CREATE EXTENSION IF NOT EXISTS pg_trgm; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Không tạo được pg_trgm: %', SQLERRM; RETURN; END;
  FOR r IN SELECT * FROM (VALUES
    ('PosProducts','Name'),
    ('PosProducts','ProductCode'),
    ('PosProducts','Barcode'),
    ('PosCustomers','Name'),
    ('PosCustomers','CustomerCode'),
    ('PosCustomers','TaxCode'),
    ('PosSaleOrders','OrderNo'),
    ('PosSaleOrders','CustomerName'),
    ('PosQuotes','QuoteNo'),
    ('PosQuotes','CustomerName'),
    ('PosPurchaseReceipts','ReceiptNo'),
    ('PosPurchaseReturns','ReturnNo'),
    ('PosPurchaseSuppliers','Name'),
    ('PosPurchaseSuppliers','SupplierCode'),
    ('PosProductSerials','SerialNumber'),
    ('PosProductSerials','Imei'),
    ('PosStockCounts','CountNo'),
    ('Employees','EmployeeCode'),
    ('Employees','LastName'),
    ('Employees','FirstName')
) AS v(tbl,col) LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=r.tbl AND column_name=r.col) THEN
      EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I USING gin ((translate(lower(%I), %L, %L)) gin_trgm_ops)',
                     'ix_vn_'||lower(r.tbl)||'_'||lower(r.col), r.tbl, r.col, f, t);
    END IF;
  END LOOP;
END $$;
