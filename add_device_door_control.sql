-- Door remote control capability (OpenDoor / CloseDoor via CONTROL DEVICE)
ALTER TABLE "DeviceInfos" ADD COLUMN IF NOT EXISTS "SupportsDoorControl" boolean;

-- Chỉ tắt cửa với PullDeny OEM (SN 131* không phải ZAM face terminal)
UPDATE "DeviceInfos" di
SET "SupportsDoorControl" = false
FROM "Devices" d
WHERE di."DeviceId" = d."Id"
  AND d."SerialNumber" LIKE '131%'
  AND di."SupportsDoorControl" IS NULL
  AND COALESCE(di."EngineProfile", '') = 'PullDeny'
  AND COALESCE(di."FirmwareVersion", '') NOT ILIKE '%ZAM%'
  AND COALESCE(di."FirmwareVersion", '') NOT ILIKE '%NF24%'
  AND COALESCE(di."FirmwareVersion", '') NOT ILIKE '%OCM%';
