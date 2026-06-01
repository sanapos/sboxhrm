SELECT a."AttendanceTime", a."PIN", a."Id" AS att_id,
       n."Timestamp" AS notif_at, n."TargetUserId"
FROM "AttendanceLogs" a
LEFT JOIN "Notifications" n ON n."RelatedEntityId" = a."Id"
WHERE a."AttendanceTime" >= '2026-05-27 20:00:00'
ORDER BY a."AttendanceTime" DESC;

SELECT d."DeviceName", d."StoreId"
FROM "Devices" d
WHERE d."Id" = '290dd675-621f-478d-97f8-fa9484aae633';

SELECT u."Email", u."Role", u."StoreId"
FROM "AspNetUsers" u
WHERE u."IsActive" AND u."Role" = 'Admin';

SELECT u."Email", t."IsDisabled", t."Platform", t."LastUsedAt"
FROM "UserDeviceTokens" t
JOIN "AspNetUsers" u ON u."Id" = t."UserId"
WHERE LOWER(u."Email") LIKE '%ngthihanh%';
