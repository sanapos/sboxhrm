-- Chỉ mục đường nóng cho cửa hàng nhiều dữ liệu.
-- Phần lớn chỉ khai báo trong cấu hình EF (HasIndex) nên CHỈ có trên DB tạo mới bằng EnsureCreated; DB dựng dần
-- bằng SQL khởi động (production) có thể thiếu → quét cả bảng. Giữ đúng tên EF để DB đã có thì bỏ qua.

-- Dòng đơn: mở / in / hủy đơn, KDS, báo cáo theo danh sách đơn, xóa hàng hóa.
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrderLines_SaleOrderId" ON "PosSaleOrderLines" ("SaleOrderId");
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrderLines_ProductId" ON "PosSaleOrderLines" ("ProductId");
-- Màn bếp (KDS) hỏi liên tục: chỉ dòng còn món chưa xong — chỉ mục nhỏ, không phình theo lịch sử.
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrderLines_Store_KitchenPending"
    ON "PosSaleOrderLines" ("StoreId", "SaleOrderId")
    WHERE "Deleted" IS NULL AND "KitchenSentQty" > "KitchenDoneQty";

-- Đơn bán: khách hàng (lịch sử / công nợ / danh sách khách), bàn đang mở, khóa sửa, vị trí hóa đơn.
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_CustomerId" ON "PosSaleOrders" ("CustomerId");
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_ServiceResourceId" ON "PosSaleOrders" ("ServiceResourceId");
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_StoreId_Status_CreatedAt" ON "PosSaleOrders" ("StoreId", "Status", "CreatedAt");
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_StoreId_InvoiceSlot" ON "PosSaleOrders" ("StoreId", "InvoiceSlot");
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_StoreId_LockExpiresAt" ON "PosSaleOrders" ("StoreId", "LockExpiresAt");
CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_StoreId_SoldByEmployeeId" ON "PosSaleOrders" ("StoreId", "SoldByEmployeeId");

-- Thẻ kho: thanh toán / hủy / trả hàng theo đơn, chứng từ kho, báo cáo theo loại + thời gian.
CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_SaleOrderId" ON "PosStockTransactions" ("SaleOrderId");
CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_StoreId_SaleOrderId_TransactionType"
    ON "PosStockTransactions" ("StoreId", "SaleOrderId", "TransactionType");
CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_StoreId_TransactionType_ReferenceNo"
    ON "PosStockTransactions" ("StoreId", "TransactionType", "ReferenceNo");
CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_Store_Type_CreatedAt"
    ON "PosStockTransactions" ("StoreId", "TransactionType", "CreatedAt");
CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_StockIssueId" ON "PosStockTransactions" ("StockIssueId");
CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_StockCountId" ON "PosStockTransactions" ("StockCountId");
CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_StockReceiptId" ON "PosStockTransactions" ("StockReceiptId");
CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_PurchaseReturnId" ON "PosStockTransactions" ("PurchaseReturnId");
CREATE INDEX IF NOT EXISTS "IX_PosStockTransactions_ProductId" ON "PosStockTransactions" ("ProductId");

-- Sổ quỹ theo thời điểm ghi (đối chiếu dòng thu bán hàng trong kỳ — báo cáo cuối ngày).
CREATE INDEX IF NOT EXISTS "IX_CashTransactions_Store_CreatedAt" ON "CashTransactions" ("StoreId", "CreatedAt");

-- Lệnh in (Agent hỏi mỗi vài giây).
CREATE INDEX IF NOT EXISTS "IX_PosPrintJobs_StoreId_Status_PrinterId_ExpiresAt"
    ON "PosPrintJobs" ("StoreId", "Status", "PrinterId", "ExpiresAt");
CREATE INDEX IF NOT EXISTS "IX_PosPrintJobs_StoreId_Status_CreatedAt" ON "PosPrintJobs" ("StoreId", "Status", "CreatedAt");
CREATE INDEX IF NOT EXISTS "IX_PosPrintJobs_PrinterId_Status" ON "PosPrintJobs" ("PrinterId", "Status");

-- Công nợ / điểm khách.
CREATE INDEX IF NOT EXISTS "IX_PosCustomerPayments_StoreId_CustomerId" ON "PosCustomerPayments" ("StoreId", "CustomerId");
CREATE INDEX IF NOT EXISTS "IX_PosCustomerPayments_SaleOrderId" ON "PosCustomerPayments" ("SaleOrderId");
CREATE INDEX IF NOT EXISTS "IX_PosCustomerPointTransactions_StoreId_CustomerId"
    ON "PosCustomerPointTransactions" ("StoreId", "CustomerId");
CREATE INDEX IF NOT EXISTS "IX_PosCustomerPointTransactions_SaleOrderId" ON "PosCustomerPointTransactions" ("SaleOrderId");

-- Quét mã ở màn bán: so khớp lower(mã) — chỉ mục cột thô không dùng được cho lower(...).
CREATE INDEX IF NOT EXISTS "IX_PosProducts_StoreId_Barcode" ON "PosProducts" ("StoreId", "Barcode");
CREATE INDEX IF NOT EXISTS "IX_PosProducts_Store_LowerCode" ON "PosProducts" ("StoreId", lower("ProductCode"));
CREATE INDEX IF NOT EXISTS "IX_PosProducts_Store_LowerBarcode" ON "PosProducts" ("StoreId", lower("Barcode"))
    WHERE "Barcode" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "IX_PosProductVariants_Store_LowerSku" ON "PosProductVariants" ("StoreId", lower("SkuCode"));
CREATE INDEX IF NOT EXISTS "IX_PosProductVariants_Store_LowerBarcode" ON "PosProductVariants" ("StoreId", lower("Barcode"))
    WHERE "Barcode" IS NOT NULL;
CREATE INDEX IF NOT EXISTS "IX_PosProductUnits_Store_LowerBarcode" ON "PosProductUnits" ("StoreId", lower("Barcode"))
    WHERE "Barcode" IS NOT NULL AND "Deleted" IS NULL;

-- Xóa thông báo theo chứng từ liên quan (xóa chấm công…) — trước đây quét toàn bảng Notifications.
CREATE INDEX IF NOT EXISTS "IX_Notifications_RelatedEntity" ON "Notifications" ("RelatedEntityId", "RelatedEntityType")
    WHERE "RelatedEntityId" IS NOT NULL;
