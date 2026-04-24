UPDATE "MobileAttendanceSettings" SET "MinFaceMatchScore" = 40;
SELECT "StoreId", "MaxPunchesPerDay", "MinPunchIntervalMinutes", "MinFaceMatchScore" FROM "MobileAttendanceSettings";
