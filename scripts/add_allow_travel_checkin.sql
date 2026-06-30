ALTER TABLE "AuthorizedMobileDevices" ADD COLUMN IF NOT EXISTS "AllowTravelCheckIn" BOOLEAN NOT NULL DEFAULT false;
