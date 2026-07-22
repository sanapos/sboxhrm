-- ADMS Phase 0/1: device capability / engine profile columns on DeviceInfos
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "Platform" character varying(100);
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "PushVersion" character varying(50);
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "DeviceModelName" character varying(200);
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "OemVendor" character varying(100);
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "EngineProfile" character varying(50);
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsUserQuery" boolean;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsAttendanceQuery" boolean;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsEnrollFingerprint" boolean;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsFaceUpdate" boolean;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "PreferStampSync" boolean NOT NULL DEFAULT false;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "CapabilityUpdatedAt" timestamp without time zone;
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "CapabilityNotes" character varying(1000);

-- Seed known pull-deny demo series (SN starts with 131) already on store devices
UPDATE "DeviceInfos" di
SET
  "EngineProfile" = 'PullDeny',
  "SupportsUserQuery" = false,
  "SupportsAttendanceQuery" = false,
  "SupportsEnrollFingerprint" = false,
  "PreferStampSync" = true,
  "CapabilityUpdatedAt" = NOW(),
  "CapabilityNotes" = COALESCE("CapabilityNotes", 'Seed PullDeny: SN 131* (demo/OEM query deny)')
FROM "Devices" d
WHERE di."DeviceId" = d."Id"
  AND d."SerialNumber" LIKE '131%'
  AND (di."EngineProfile" IS NULL OR di."EngineProfile" = '' OR di."EngineProfile" = 'Default');
