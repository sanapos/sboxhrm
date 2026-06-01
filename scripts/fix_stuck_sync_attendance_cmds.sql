-- Đóng lệnh SyncAttendances kẹt ở Sent (Status=1) — chúng chặn toàn bộ push chấm công.
UPDATE "DeviceCommands"
SET "Status" = 2
WHERE "CommandType" = 7
  AND "Status" = 1
  AND "SentAt" < NOW() - interval '10 minutes';

SELECT d."DeviceName", dc."Status", dc."SentAt"
FROM "DeviceCommands" dc
JOIN "Devices" d ON d."Id" = dc."DeviceId"
WHERE dc."CommandType" = 7 AND dc."Status" IN (0, 1)
ORDER BY dc."CreatedAt" DESC
LIMIT 10;
