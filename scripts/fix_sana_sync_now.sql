UPDATE "DeviceCommands"
SET "Status" = 2
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
  AND "CommandType" = 7
  AND "Status" = 1;

SELECT "Status", COUNT(*) FROM "DeviceCommands"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633' AND "CommandType" = 7
GROUP BY "Status";
