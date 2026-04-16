ALTER TABLE "LicenseKeys" ADD COLUMN IF NOT EXISTS "ServicePackageId" uuid REFERENCES "ServicePackages"("Id");
