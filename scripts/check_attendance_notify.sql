-- Diagnose attendance notifications
SELECT NOW() AS server_now, NOW() AT TIME ZONE 'Asia/Ho_Chi_Minh' AS vn_now;

SELECT COUNT(*) AS att_24h
FROM "AttendanceLogs"
WHERE "AttendanceTime" >= NOW() - interval '24 hours';

SELECT "AttendanceTime", "PIN", "VerifyMode", "DeviceId"
FROM "AttendanceLogs"
ORDER BY "AttendanceTime" DESC
LIMIT 8;

SELECT COUNT(*) AS notif_att_24h
FROM "Notifications"
WHERE "CategoryCode" = 'attendance'
  AND "Timestamp" >= NOW() - interval '24 hours';

SELECT "Timestamp", "Title", "Message", "TargetUserId"
FROM "Notifications"
WHERE "CategoryCode" = 'attendance'
ORDER BY "Timestamp" DESC
LIMIT 8;

SELECT COUNT(*) AS active_fcm
FROM "UserDeviceTokens"
WHERE NOT "IsDisabled";

SELECT u."Email", p."CategoryCode", p."IsEnabled"
FROM "NotificationPreferences" p
JOIN "AspNetUsers" u ON u."Id" = p."UserId"
WHERE p."CategoryCode" = 'attendance' AND NOT p."IsEnabled"
LIMIT 10;

SELECT COUNT(*) AS pending_sync_cmd
FROM "DeviceCommands"
WHERE "CommandType" = 7 AND "Status" = 0;
