-- Tạm thời tắt Google Drive — mọi upload dùng wwwroot trên server API.
UPDATE "AppSettings"
SET "Value" = 'false', "LastModified" = NOW()
WHERE "Key" = 'google_drive_enabled';

SELECT "Key", "Value", "StoreId"
FROM "AppSettings"
WHERE "Key" LIKE 'google_drive%'
ORDER BY "Key";
