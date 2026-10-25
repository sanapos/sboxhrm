-- Add WiFi attendance columns
-- MobileAttendanceSettings: EnableWifi
ALTER TABLE "MobileAttendanceSettings" ADD COLUMN IF NOT EXISTS "EnableWifi" boolean NOT NULL DEFAULT false;

-- MobileWorkLocations: WifiSsid, WifiBssid, AllowedIpRange
ALTER TABLE "MobileWorkLocations" ADD COLUMN IF NOT EXISTS "WifiSsid" character varying(200);
ALTER TABLE "MobileWorkLocations" ADD COLUMN IF NOT EXISTS "WifiBssid" character varying(200);
ALTER TABLE "MobileWorkLocations" ADD COLUMN IF NOT EXISTS "AllowedIpRange" character varying(500);

-- MobileAttendanceRecords: WifiSsid, WifiIpAddress
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "WifiSsid" character varying(200);
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "WifiIpAddress" character varying(100);
