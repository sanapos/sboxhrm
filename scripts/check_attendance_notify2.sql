SELECT d."DeviceName", d."SerialNumber", dc."CommandType", dc."Status", dc."CreatedAt"
FROM "DeviceCommands" dc
JOIN "Devices" d ON d."Id" = dc."DeviceId"
WHERE dc."DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
ORDER BY dc."CreatedAt" DESC
LIMIT 10;

SELECT u."Email", COUNT(n."Id") AS att_notif_today
FROM "AspNetUsers" u
LEFT JOIN "Notifications" n ON n."TargetUserId" = u."Id"
  AND n."CategoryCode" = 'attendance'
  AND n."Timestamp" >= NOW() - interval '24 hours'
WHERE LOWER(u."Email") LIKE '%ngthihanh%' OR u."Role" = 'Admin'
GROUP BY u."Email"
ORDER BY att_notif_today DESC
LIMIT 10;

SELECT u."Email", t."Token", t."IsDisabled", t."Platform"
FROM "UserDeviceTokens" t
JOIN "AspNetUsers" u ON u."Id" = t."UserId"
WHERE LOWER(u."Email") LIKE '%ngthihanh%';

SELECT COUNT(*) FROM "Notifications"
WHERE "Timestamp" >= NOW() - interval '3 hours'
  AND "Message" LIKE '%21:2%';
