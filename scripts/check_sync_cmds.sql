SELECT d."DeviceName", dc."Status", dc."CommandType", dc."CreatedAt", dc."SentAt"
FROM "DeviceCommands" dc
JOIN "Devices" d ON d."Id" = dc."DeviceId"
WHERE dc."CommandType" = 7 AND dc."Status" IN (0, 1)
ORDER BY dc."CreatedAt" DESC
LIMIT 15;
