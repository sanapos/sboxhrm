-- Xóa mềm các punch cách nhau < 5 phút (giữ lại punch đầu tiên trong cụm)
WITH flagged AS (
  SELECT "Id",
         "PunchTime" - LAG("PunchTime") OVER (
           PARTITION BY "OdooEmployeeId", "StoreId"
           ORDER BY "PunchTime"
         ) AS gap
  FROM "MobileAttendanceRecords"
  WHERE "Deleted" IS NULL
)
UPDATE "MobileAttendanceRecords" r
SET "Deleted" = NOW()
FROM flagged f
WHERE r."Id" = f."Id"
  AND f.gap IS NOT NULL
  AND f.gap < INTERVAL '5 minutes';

SELECT COUNT(*) AS cleaned FROM "MobileAttendanceRecords" WHERE "Deleted" > NOW() - INTERVAL '1 minute';
