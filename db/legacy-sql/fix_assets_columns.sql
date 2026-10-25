ALTER TABLE "Assets" ADD COLUMN IF NOT EXISTS "QrCode" text;
ALTER TABLE "Assets" ADD COLUMN IF NOT EXISTS "Size" text;
ALTER TABLE "Assets" ADD COLUMN IF NOT EXISTS "Color" text;
UPDATE "Assets" SET "QrCode" = "AssetCode" WHERE "QrCode" IS NULL;
CREATE INDEX IF NOT EXISTS "IX_Assets_QrCode" ON "Assets" ("QrCode");
