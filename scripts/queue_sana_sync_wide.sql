INSERT INTO "DeviceCommands" (
  "Id", "DeviceId", "CommandId", "Command", "Priority", "CommandType", "Status",
  "ObjectReferenceId", "CreatedAt", "UpdatedAt"
)
VALUES (
  gen_random_uuid(),
  '290dd675-621f-478d-97f8-fa9484aae633',
  (EXTRACT(EPOCH FROM NOW()) * 1000000)::bigint,
  'DATA QUERY ATTLOG StartTime=2021-05-27T00:00:00	EndTime=2026-05-28T23:59:59',
  10,
  7,
  0,
  '00000000-0000-0000-0000-000000000000',
  NOW(),
  NOW()
)
RETURNING "CommandId", "Command";
