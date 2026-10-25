-- Add StoreId column to AppSettings
ALTER TABLE "AppSettings" ADD COLUMN IF NOT EXISTS "StoreId" uuid NULL;

-- Add foreign key 
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_AppSettings_Stores_StoreId') THEN
    ALTER TABLE "AppSettings" ADD CONSTRAINT "FK_AppSettings_Stores_StoreId" 
      FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE;
  END IF;
END $$;

-- Drop old unique index on Key only
DROP INDEX IF EXISTS "IX_AppSettings_Key";

-- Create composite unique index on (StoreId, Key)
DROP INDEX IF EXISTS "IX_AppSettings_StoreId_Key"; 
CREATE UNIQUE INDEX "IX_AppSettings_StoreId_Key" ON "AppSettings" ("StoreId", "Key");

-- Create index on StoreId for query filtering
DROP INDEX IF EXISTS "IX_AppSettings_StoreId";
CREATE INDEX "IX_AppSettings_StoreId" ON "AppSettings" ("StoreId");

-- Update existing settings with a default store if needed
DO $$ 
DECLARE 
  default_store_id uuid;
BEGIN
  SELECT "Id" INTO default_store_id FROM "Stores" LIMIT 1;
  IF default_store_id IS NOT NULL THEN
    UPDATE "AppSettings" SET "StoreId" = default_store_id WHERE "StoreId" IS NULL;
  END IF;
END $$;
