SELECT "CommandType", "Command", "Status", "CreatedAt"
FROM "DeviceCommands"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
  AND ("Command" LIKE '%CLEAR%' OR "CommandType" = 3)
ORDER BY "CreatedAt" DESC
LIMIT 10;
