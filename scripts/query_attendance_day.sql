-- Mọi phiếu liên quan 01/05/2026
SELECT "Id", "Action", "Status", "OldDate", "OldTime", "NewDate", "NewTime", "AttendanceId", "Reason", "ApprovedDate", "CreatedAt"
FROM "AttendanceCorrectionRequests"
WHERE "EmployeeCode" = '0374667133'
  AND "OldDate"::date = '2026-05-01'
ORDER BY "CreatedAt";

-- Có log 06:40 từng tồn tại? (Note, mọi ngày)
SELECT "Id", "AttendanceTime", "Note", "CreatedAt"
FROM "AttendanceLogs"
WHERE "PIN" = '80' AND "AttendanceTime"::time BETWEEN '06:35' AND '06:45'
ORDER BY "AttendanceTime" DESC
LIMIT 20;
