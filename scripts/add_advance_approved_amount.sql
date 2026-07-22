-- Cho phép quản lý duyệt ứng lương thấp hơn số tiền yêu cầu.
-- ApprovedAmount = null → dùng Amount (phiếu cũ / duyệt đủ).

ALTER TABLE "AdvanceRequests"
  ADD COLUMN IF NOT EXISTS "ApprovedAmount" numeric(18,2) NULL;

-- Xác nhận cột đã có
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'AdvanceRequests'
  AND column_name IN ('Amount', 'ApprovedAmount')
ORDER BY column_name;
