SELECT "Id", "ShiftId", "ShiftIds", "CreatedAt"
FROM "Leaves"
ORDER BY "CreatedAt" DESC LIMIT 5;

-- Check if ShiftIds column exists
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'Leaves' AND column_name IN ('ShiftId', 'ShiftIds');
