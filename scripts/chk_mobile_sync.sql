SELECT "Id", "SerialNumber", "StoreId", "DeviceName" FROM "Devices" WHERE "SerialNumber" LIKE 'MOBILE%' ORDER BY "SerialNumber";
SELECT COUNT(*) AS mobile_records_today FROM "MobileAttendanceRecords" WHERE "Deleted" IS NULL AND "PunchTime"::date = CURRENT_DATE;
SELECT COUNT(*) AS synced_logs_today FROM "AttendanceLogs" WHERE "MobileAttendanceRecordId" IS NOT NULL AND "AttendanceTime"::date = CURRENT_DATE;
SELECT r."Id", r."Status", LEFT(r."OdooEmployeeId", 36) AS emp, r."PunchTime" FROM "MobileAttendanceRecords" r WHERE r."Deleted" IS NULL ORDER BY r."PunchTime" DESC LIMIT 8;
