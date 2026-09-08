SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'AttendanceLogs' AND column_name IN ('MobileAttendanceRecordId', 'PIN', 'EmployeeId');
