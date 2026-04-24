SELECT "OdooEmployeeId", "PunchTime", "PunchType", "CreatedAt" 
FROM "MobileAttendanceRecords" 
WHERE "Deleted" IS NULL 
  AND "PunchTime" > NOW() - INTERVAL '30 minutes' 
ORDER BY "PunchTime" DESC LIMIT 20;
