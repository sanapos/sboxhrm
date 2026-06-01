-- Dọn trùng chấm công thô: giữ bản ghi CreatedAt sớm nhất mỗi (DeviceId, PIN, AttendanceTime).
-- Chạy trước khi tạo unique index nếu migration chưa áp dụng.

DELETE FROM "AttendanceLogs" a
WHERE a."Id" IN (
    SELECT al."Id"
    FROM (
        SELECT "Id",
               ROW_NUMBER() OVER (
                   PARTITION BY "DeviceId", "PIN", "AttendanceTime"
                   ORDER BY "CreatedAt" ASC, "Id" ASC
               ) AS rn
        FROM "AttendanceLogs"
    ) al
    WHERE al.rn > 1
);

SELECT COUNT(*) AS remaining_rows FROM "AttendanceLogs";
