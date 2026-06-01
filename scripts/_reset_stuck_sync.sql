UPDATE "DeviceCommands"
SET "Status" = 3, "SentAt" = NULL
WHERE "DeviceId" = '54931289-c9d5-49cb-b615-0c03726c473a'
  AND "CommandType" = 7
  AND "Status" IN (0, 1);

SELECT "Status", COUNT(*) FROM "DeviceCommands"
WHERE "DeviceId" = '54931289-c9d5-49cb-b615-0c03726c473a' AND "CommandType" = 7
GROUP BY "Status";
