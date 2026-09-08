SELECT "Id", "PunchTime", "FaceImageUrl", "SitePhotoUrl", "StoreId"
FROM "MobileAttendanceRecords"
WHERE "Id" = '9ed89df5-5b1a-447a-a785-8dda09882354';

SELECT COUNT(*) AS with_site FROM "MobileAttendanceRecords"
WHERE "SitePhotoUrl" IS NOT NULL AND trim("SitePhotoUrl") <> '';
