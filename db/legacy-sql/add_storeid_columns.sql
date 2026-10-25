-- Migration: Add StoreId column to entities that were missing it
-- This script adds StoreId foreign key to BankAccounts, CashTransactions, 
-- TransactionCategories, AppSettings, and SystemConfigurations tables.
-- After adding, it populates StoreId from the first available store for existing data.

-- Step 1: Add StoreId columns (nullable UUID with FK to Stores)

ALTER TABLE "BankAccounts" ADD COLUMN IF NOT EXISTS "StoreId" uuid;
ALTER TABLE "CashTransactions" ADD COLUMN IF NOT EXISTS "StoreId" uuid;
ALTER TABLE "TransactionCategories" ADD COLUMN IF NOT EXISTS "StoreId" uuid;
ALTER TABLE "AppSettings" ADD COLUMN IF NOT EXISTS "StoreId" uuid;
ALTER TABLE "SystemConfigurations" ADD COLUMN IF NOT EXISTS "StoreId" uuid;

-- Step 2: Add foreign key constraints

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_BankAccounts_Stores_StoreId') THEN
        ALTER TABLE "BankAccounts" ADD CONSTRAINT "FK_BankAccounts_Stores_StoreId" 
            FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_CashTransactions_Stores_StoreId') THEN
        ALTER TABLE "CashTransactions" ADD CONSTRAINT "FK_CashTransactions_Stores_StoreId" 
            FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_TransactionCategories_Stores_StoreId') THEN
        ALTER TABLE "TransactionCategories" ADD CONSTRAINT "FK_TransactionCategories_Stores_StoreId" 
            FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_AppSettings_Stores_StoreId') THEN
        ALTER TABLE "AppSettings" ADD CONSTRAINT "FK_AppSettings_Stores_StoreId" 
            FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_SystemConfigurations_Stores_StoreId') THEN
        ALTER TABLE "SystemConfigurations" ADD CONSTRAINT "FK_SystemConfigurations_Stores_StoreId" 
            FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE SET NULL;
    END IF;
END $$;

-- Step 3: Populate StoreId for existing data using the first store
-- (For single-store deployments, all existing data belongs to the first store)

UPDATE "BankAccounts" SET "StoreId" = (SELECT "Id" FROM "Stores" ORDER BY "CreatedAt" LIMIT 1) 
    WHERE "StoreId" IS NULL;

UPDATE "CashTransactions" SET "StoreId" = (SELECT s."StoreId" FROM "AspNetUsers" s WHERE s."Id" = "CreatedByUserId" LIMIT 1) 
    WHERE "StoreId" IS NULL AND "CreatedByUserId" IS NOT NULL;

UPDATE "TransactionCategories" SET "StoreId" = (SELECT "Id" FROM "Stores" ORDER BY "CreatedAt" LIMIT 1) 
    WHERE "StoreId" IS NULL;

UPDATE "AppSettings" SET "StoreId" = (SELECT "Id" FROM "Stores" ORDER BY "CreatedAt" LIMIT 1) 
    WHERE "StoreId" IS NULL;

UPDATE "SystemConfigurations" SET "StoreId" = (SELECT "Id" FROM "Stores" ORDER BY "CreatedAt" LIMIT 1) 
    WHERE "StoreId" IS NULL;

-- Step 4: Create indexes for StoreId columns (performance)

CREATE INDEX IF NOT EXISTS "IX_BankAccounts_StoreId" ON "BankAccounts"("StoreId");
CREATE INDEX IF NOT EXISTS "IX_CashTransactions_StoreId" ON "CashTransactions"("StoreId");
CREATE INDEX IF NOT EXISTS "IX_TransactionCategories_StoreId" ON "TransactionCategories"("StoreId");
CREATE INDEX IF NOT EXISTS "IX_AppSettings_StoreId" ON "AppSettings"("StoreId");
CREATE INDEX IF NOT EXISTS "IX_SystemConfigurations_StoreId" ON "SystemConfigurations"("StoreId");
