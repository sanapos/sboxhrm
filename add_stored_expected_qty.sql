-- Add StoredExpectedQuantity column to AssetInventoryItems
ALTER TABLE "AssetInventoryItems" ADD COLUMN IF NOT EXISTS "StoredExpectedQuantity" integer NOT NULL DEFAULT 0;

-- Backfill existing items with Asset.Quantity
UPDATE "AssetInventoryItems" aii
SET "StoredExpectedQuantity" = COALESCE(a."Quantity", 0)
FROM "Assets" a
WHERE aii."AssetId" = a."Id" AND aii."StoredExpectedQuantity" = 0;
