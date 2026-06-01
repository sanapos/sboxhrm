-- Xóa thông báo chấm công mà bản ghi AttendanceLogs đã bị xóa (mồ côi)
DELETE FROM "Notifications" n
WHERE n."RelatedEntityType" = 'Attendance'
  AND n."RelatedEntityId" IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM "AttendanceLogs" a WHERE a."Id" = n."RelatedEntityId"
  );

SELECT COUNT(*) AS remaining_attendance_notifications
FROM "Notifications"
WHERE "CategoryCode" = 'attendance' OR "RelatedEntityType" = 'Attendance';
