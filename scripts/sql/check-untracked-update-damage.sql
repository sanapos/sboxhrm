-- Kiểm tra (CHỈ ĐỌC) dữ liệu sai do lỗi «sửa không lưu» (DbContext NoTracking, đã sửa 27/10/2026).
-- Chạy:  psql -h <host> -U <user> -d <db> -f scripts/sql/check-untracked-update-damage.sql
-- Không có dòng nào trả về = không có dữ liệu cần dọn.

-- 1) Định lượng NVL: lưu lại định lượng không xóa dòng cũ → một món còn dòng từ nhiều lần lưu, trừ kho NVL nhiều lần.
--    Mỗi lần lưu tạo cả bộ dòng mới cùng lúc; dòng cũ hơn lần lưu gần nhất quá 5 giây là dòng lẽ ra đã bị xóa.
WITH active AS (
    SELECT "Id", "StoreId", "ParentProductId", "CreatedAt"
    FROM "PosProductRecipeLines"
    WHERE "Deleted" IS NULL
), latest AS (
    SELECT "ParentProductId", max("CreatedAt") AS last_save FROM active GROUP BY "ParentProductId"
)
SELECT a."StoreId", s."Name" AS cua_hang, p."Name" AS mon, count(*) AS dong_cu_con_hieu_luc,
       min(a."CreatedAt") AS tu, max(a."CreatedAt") AS den, l.last_save AS lan_luu_gan_nhat
FROM active a
JOIN latest l ON l."ParentProductId" = a."ParentProductId"
LEFT JOIN "PosProducts" p ON p."Id" = a."ParentProductId"
LEFT JOIN "Stores" s ON s."Id" = a."StoreId"
WHERE a."CreatedAt" < l.last_save - interval '5 seconds'
GROUP BY a."StoreId", s."Name", p."Name", l.last_save
ORDER BY dong_cu_con_hieu_luc DESC;

-- 2) Công tác phí — xử lý khoản dư: phiếu hoạch toán không được đánh dấu «đã xử lý» → có thể sinh trùng
--    ứng lương / giao dịch lương / phiếu thu hoàn cho CÙNG một phiếu hoạch toán.
SELECT 'AdvanceRequests' AS bang, "Note" AS ghi_chu, count(*) AS so_ban_ghi, min("CreatedAt") AS tu, max("CreatedAt") AS den
FROM "AdvanceRequests"
WHERE "Note" LIKE 'Tự động tạo từ quyết toán công tác phí #%' AND "Deleted" IS NULL
  AND "Status" <> 3 -- bỏ đơn đã hủy
GROUP BY "Note" HAVING count(*) > 1
UNION ALL
SELECT 'PaymentTransactions', "Note", count(*), min("CreatedAt"), max("CreatedAt")
FROM "PaymentTransactions"
WHERE "Note" LIKE 'Tự động tạo từ quyết toán công tác phí #%'
GROUP BY "Note" HAVING count(*) > 1
UNION ALL
SELECT 'CashTransactions', "InternalNote", count(*), min("CreatedAt"), max("CreatedAt")
FROM "CashTransactions"
WHERE ("InternalNote" LIKE 'Tự động tạo từ thu hoàn ứng công tác #%'
       OR "InternalNote" LIKE 'Tự động tạo từ quyết toán công tác phí #%')
  AND "Deleted" IS NULL AND "IsActive"
GROUP BY "InternalNote" HAVING count(*) > 1
ORDER BY 1, 3 DESC;

-- 3) Thông tin: lệnh máy chấm công kẹt ở Created / Sent quá 1 ngày (trước đây máy trả kết quả nhưng trạng thái không lưu).
SELECT "Status" AS trang_thai, count(*) AS so_lenh, min("CreatedAt") AS cu_nhat
FROM "DeviceCommands"
WHERE "Status" IN (0, 1) AND "CreatedAt" < now() - interval '1 day'
GROUP BY "Status";
