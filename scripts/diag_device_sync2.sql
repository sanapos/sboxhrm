SELECT dc."CommandType", dc."Status", dc."Command", dc."ResponseData", dc."ErrorMessage", dc."Return",
       d."SerialNumber", dc."CreatedAt", dc."SentAt", dc."CompletedAt"
FROM "DeviceCommands" dc
JOIN "Devices" d ON d."Id" = dc."DeviceId"
WHERE dc."CommandType" = 8
  AND dc."CreatedAt" > NOW() - INTERVAL '3 hours'
ORDER BY dc."CreatedAt" DESC
LIMIT 10;

SELECT "Table", COUNT(*) FROM (
  SELECT 'need_post_log' as x
) t;
