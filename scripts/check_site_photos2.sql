SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE "SitePhotoUrl" IS NOT NULL AND "SitePhotoUrl" <> '') AS with_site
FROM "MobileAttendanceRecords"
WHERE "Deleted" IS NULL;

SELECT "PunchTime", "StoreId", LEFT("SitePhotoUrl", 120) AS site_path
FROM "MobileAttendanceRecords"
WHERE "SitePhotoUrl" IS NOT NULL AND "SitePhotoUrl" <> ''
ORDER BY "PunchTime" DESC
LIMIT 8;
