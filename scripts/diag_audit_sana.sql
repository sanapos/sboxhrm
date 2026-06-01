SELECT column_name FROM information_schema.columns
WHERE table_name = 'AuditLogs' ORDER BY ordinal_position;

SELECT "Action", "EntityType", "Details", "CreatedAt", "UserEmail"
FROM "AuditLogs"
WHERE ("Details"::text ILIKE '%290dd675%' OR "Details"::text ILIKE '%SANA%' OR "Details"::text ILIKE '%Attendance%')
  AND "CreatedAt" >= '2026-05-27 15:00:00'
ORDER BY "CreatedAt" DESC
LIMIT 25;
