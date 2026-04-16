SELECT "Id", "EmployeeId", "EmployeeName", "JourneyDate", "StartTime", "EndTime", "Status", "TotalDistanceKm", "CheckedInCount", "AssignedCount" FROM "JourneyTrackings" ORDER BY "JourneyDate" DESC LIMIT 10;
SELECT "Id", "EmployeeId", "LocationId", "DayOfWeek", "IsActive" FROM "FieldLocationAssignments" WHERE "Deleted" IS NULL LIMIT 10;
SELECT "Id", "Name", "Address", "RegisteredByEmployeeId", "IsApproved" FROM "FieldLocations" WHERE "Deleted" IS NULL LIMIT 10;
