-- Dọn dòng định lượng NVL cũ còn hiệu lực (lỗi «sửa không lưu»: lưu lại định lượng không xóa dòng cũ → trừ kho NVL nhiều lần).
-- Quy tắc: mỗi món chỉ giữ các dòng của LẦN LƯU GẦN NHẤT (màn Định lượng là nơi duy nhất tạo dòng, mỗi lần lưu tạo cả bộ
-- mới cùng lúc); dòng tạo sớm hơn lần lưu gần nhất quá 5 giây được xóa mềm như app lẽ ra đã làm.
--
-- MẶC ĐỊNH CHẠY THỬ: cuối file là ROLLBACK. Xem số dòng / danh sách món, đúng thì đổi ROLLBACK → COMMIT rồi chạy lại.
-- Chạy:  psql -h <host> -U <user> -d <db> -f scripts/sql/cleanup-stale-recipe-lines.sql

BEGIN;

CREATE TEMP TABLE stale_recipe_lines ON COMMIT DROP AS
WITH active AS (
    SELECT "Id", "StoreId", "ParentProductId", "CreatedAt"
    FROM "PosProductRecipeLines"
    WHERE "Deleted" IS NULL
), latest AS (
    SELECT "ParentProductId", max("CreatedAt") AS last_save FROM active GROUP BY "ParentProductId"
)
SELECT a."Id", a."StoreId", a."ParentProductId"
FROM active a
JOIN latest l ON l."ParentProductId" = a."ParentProductId"
WHERE a."CreatedAt" < l.last_save - interval '5 seconds';

-- Xem trước: cửa hàng / món / số dòng sẽ xóa mềm.
SELECT s."Name" AS cua_hang, p."Name" AS mon, count(*) AS so_dong_xoa
FROM stale_recipe_lines x
LEFT JOIN "PosProducts" p ON p."Id" = x."ParentProductId"
LEFT JOIN "Stores" s ON s."Id" = x."StoreId"
GROUP BY s."Name", p."Name"
ORDER BY so_dong_xoa DESC;

UPDATE "PosProductRecipeLines" r
SET "Deleted" = now() AT TIME ZONE 'utc', "DeletedBy" = 'cleanup-2026-10-27', "IsActive" = false
FROM stale_recipe_lines x
WHERE r."Id" = x."Id";

SELECT count(*) AS tong_dong_da_xoa_mem FROM stale_recipe_lines;

ROLLBACK; -- đổi thành COMMIT sau khi đã xem kết quả phía trên
