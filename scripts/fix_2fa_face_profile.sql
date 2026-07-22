-- Reclassify 2FA ZAM70 face terminal (was wrongly PullDeny due to SN 131*)
UPDATE "DeviceInfos" di
SET
  "EngineProfile" = 'AndroidVisibleLight',
  "SupportsFaceUpdate" = true,
  "SupportsEnrollFingerprint" = false,
  "PreferStampSync" = COALESCE("PreferStampSync", false),
  "CapabilityUpdatedAt" = NOW(),
  "CapabilityNotes" = 'ZAM70 face: remote face via ENROLL_FP FID=50 BIODATAFLAG=8'
FROM "Devices" d
WHERE di."DeviceId" = d."Id"
  AND d."SerialNumber" = '1313254901006';
