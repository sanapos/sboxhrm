SELECT "PunchTime", "Status",
       CASE WHEN "FaceImageUrl" IS NOT NULL AND "FaceImageUrl" <> '' THEN 'Y' ELSE 'N' END AS face,
       CASE WHEN "SitePhotoUrl" IS NOT NULL AND "SitePhotoUrl" <> '' THEN 'Y' ELSE 'N' END AS site,
       LEFT(COALESCE("SitePhotoUrl", ''), 100) AS site_path
FROM "MobileAttendanceRecords"
WHERE "Deleted" IS NULL
ORDER BY "PunchTime" DESC
LIMIT 12;
