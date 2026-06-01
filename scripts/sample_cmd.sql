SELECT "CommandId", "ObjectReferenceId", "Command", "Status", "CommandType"
FROM "DeviceCommands"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
ORDER BY "CreatedAt" DESC LIMIT 2;
