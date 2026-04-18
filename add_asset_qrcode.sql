-- Add QrCode column to Assets table for QR code scanning
ALTER TABLE "Assets" ADD COLUMN IF NOT EXISTS "QrCode" text;

-- Default QrCode to AssetCode for existing assets
UPDATE "Assets" SET "QrCode" = "AssetCode" WHERE "QrCode" IS NULL;

-- Index for quick QR/code lookup
CREATE INDEX IF NOT EXISTS "IX_Assets_QrCode" ON "Assets" ("QrCode");
