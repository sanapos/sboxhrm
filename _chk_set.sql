SELECT "Command","Status","Return",left(coalesce("ErrorMessage",''),60)
FROM "DeviceCommands"
WHERE "DeviceId"='5e0eafc6-5103-4728-81b0-ad3bf2ffeab1'
  AND "CreatedAt">NOW()-INTERVAL '5 minutes'
ORDER BY "CreatedAt";