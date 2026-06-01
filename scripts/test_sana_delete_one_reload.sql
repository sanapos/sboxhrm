-- Step 1: snapshot before
SELECT 'BEFORE' AS phase, COUNT(*) AS server_total
FROM "AttendanceLogs" WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633';

SELECT "Id", "AttendanceTime", "PIN"
FROM "AttendanceLogs"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
  AND "AttendanceTime" >= '2026-05-27' AND "AttendanceTime" < '2026-05-28';

-- Step 2: delete one May 27 row + linked notifications
DO $$
DECLARE
  att_id uuid;
BEGIN
  SELECT "Id" INTO att_id
  FROM "AttendanceLogs"
  WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
    AND "AttendanceTime" >= '2026-05-27' AND "AttendanceTime" < '2026-05-28'
  ORDER BY "AttendanceTime" DESC
  LIMIT 1;

  IF att_id IS NULL THEN
    RAISE NOTICE 'No May 27 row to delete';
    RETURN;
  END IF;

  DELETE FROM "Notifications"
  WHERE "RelatedEntityType" = 'Attendance' AND "RelatedEntityId" = att_id;

  DELETE FROM "AttendanceLogs" WHERE "Id" = att_id;
  RAISE NOTICE 'Deleted attendance %', att_id;
END $$;

SELECT 'AFTER_DELETE' AS phase, COUNT(*) AS server_total
FROM "AttendanceLogs" WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633';

SELECT COUNT(*) AS may27_remaining
FROM "AttendanceLogs"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633'
  AND "AttendanceTime" >= '2026-05-27' AND "AttendanceTime" < '2026-05-28';

-- Step 3: queue SyncAttendances (same as API: 5 years range)
INSERT INTO "DeviceCommands" (
  "Id", "DeviceId", "Command", "Priority", "CommandType", "Status", "CreatedAt", "UpdatedAt"
)
VALUES (
  gen_random_uuid(),
  '290dd675-621f-478d-97f8-fa9484aae633',
  'DATA QUERY ATTLOG StartTime=2021-05-27T00:00:00	EndTime=2026-05-28T23:59:59',
  10,
  7,
  0,
  NOW(),
  NOW()
);

SELECT 'COMMAND_QUEUED' AS phase, "Id", "Command", "Status"
FROM "DeviceCommands"
WHERE "DeviceId" = '290dd675-621f-478d-97f8-fa9484aae633' AND "CommandType" = 7 AND "Status" = 0
ORDER BY "CreatedAt" DESC LIMIT 1;
