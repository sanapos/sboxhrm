UPDATE "MobileAttendanceSettings" SET "MinFaceMatchScore" = 80;
SELECT "StoreId", "MaxPunchesPerDay", "MinPunchIntervalMinutes", "MinFaceMatchScore" FROM "MobileAttendanceSettings";
