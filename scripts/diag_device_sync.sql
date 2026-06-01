SELECT d."SerialNumber", d."DeviceName", s."Code" as store_code, d."LastOnline", d."DeviceStatus",
       (SELECT COUNT(*) FROM "DeviceUsers" du WHERE du."DeviceId" = d."Id") as device_user_count
FROM "Devices" d
LEFT JOIN "Stores" s ON s."Id" = d."StoreId"
ORDER BY d."LastOnline" DESC NULLS LAST
LIMIT 15;

SELECT "CommandType", "Status", LEFT("Command", 40) as cmd, "CreatedAt", "SentAt", "CompletedAt"
FROM "DeviceCommands"
WHERE "CommandType" = 8
ORDER BY "CreatedAt" DESC
LIMIT 15;

SELECT COUNT(*) as total_device_users FROM "DeviceUsers";
