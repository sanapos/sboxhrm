SELECT "CommandType", "Command", "Status", "CreatedAt"
FROM "DeviceCommands"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
  AND ("Command" ILIKE '%CLEAR%' OR "CommandType" IN (1, 8))
ORDER BY "CreatedAt" DESC
LIMIT 10;

-- Audit / activity nếu có
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name ILIKE '%audit%';
