SELECT "StoreId", "RequirePhotoProof", "EnableFaceId", "AutoApproveInRange"
FROM "MobileAttendanceSettings"
WHERE "Deleted" IS NULL
LIMIT 5;

SELECT "DeviceId", "RequirePhotoProof", "IsAuthorized"
FROM "MobileDevices"
WHERE "Deleted" IS NULL
ORDER BY "LastUsedAt" DESC NULLS LAST
LIMIT 5;
