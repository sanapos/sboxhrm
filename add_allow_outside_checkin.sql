-- Add AllowOutsideCheckIn column to AuthorizedMobileDevices table
-- Allows specific devices to check in outside company location (bypass GPS & WiFi validation)
ALTER TABLE "AuthorizedMobileDevices" ADD COLUMN IF NOT EXISTS "AllowOutsideCheckIn" BOOLEAN NOT NULL DEFAULT FALSE;
