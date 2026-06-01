\echo '=== Google Drive AppSettings ==='
SELECT "Key",
  CASE
    WHEN "Key" = 'google_drive_credentials_json' THEN
      CASE WHEN COALESCE(TRIM("Value"), '') <> '' THEN 'configured (' || length("Value")::text || ' chars)' ELSE 'empty' END
    WHEN "Key" = 'google_drive_folder_id' THEN COALESCE(LEFT("Value", 50), '(null)')
    ELSE COALESCE("Value", '(null)')
  END AS value_preview,
  "StoreId"
FROM "AppSettings"
WHERE "Key" LIKE 'google_drive%'
ORDER BY "Key", "StoreId" NULLS FIRST;

\echo '=== Sample FaceImageUrl (latest 5) ==='
SELECT "Status", LEFT("FaceImageUrl", 120) AS face_path, "PunchTime"
FROM "MobileAttendanceRecords"
WHERE "FaceImageUrl" IS NOT NULL AND TRIM("FaceImageUrl") <> ''
ORDER BY "PunchTime" DESC
LIMIT 5;

\echo '=== Face path stats ==='
SELECT
  COUNT(*) FILTER (WHERE "FaceImageUrl" IS NOT NULL AND TRIM("FaceImageUrl") <> '') AS total_with_face,
  COUNT(*) FILTER (WHERE "FaceImageUrl" LIKE 'gdrive://%') AS gdrive_paths,
  COUNT(*) FILTER (WHERE "FaceImageUrl" IS NOT NULL AND TRIM("FaceImageUrl") <> '' AND "FaceImageUrl" NOT LIKE 'gdrive://%') AS local_style_paths
FROM "MobileAttendanceRecords";
