-- Create StockTransaction table for stock in/out/adjustment tracking
CREATE TABLE IF NOT EXISTS "StockTransactions" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "AssetId" uuid NOT NULL,
    "TransactionType" integer NOT NULL DEFAULT 0,
    "Quantity" integer NOT NULL DEFAULT 0,
    "BalanceAfter" integer NOT NULL DEFAULT 0,
    "Reason" text,
    "ReferenceCode" text,
    "RelatedInventoryId" uuid,
    "PerformedById" uuid,
    "Notes" text,
    "StoreId" uuid NOT NULL,
    "TransactionDate" timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT "PK_StockTransactions" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_StockTransactions_Assets_AssetId" FOREIGN KEY ("AssetId") REFERENCES "Assets" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_StockTransactions_AssetInventories_RelatedInventoryId" FOREIGN KEY ("RelatedInventoryId") REFERENCES "AssetInventories" ("Id") ON DELETE SET NULL,
    CONSTRAINT "FK_StockTransactions_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS "IX_StockTransactions_AssetId" ON "StockTransactions" ("AssetId");
CREATE INDEX IF NOT EXISTS "IX_StockTransactions_StoreId" ON "StockTransactions" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_StockTransactions_TransactionDate" ON "StockTransactions" ("TransactionDate" DESC);
CREATE INDEX IF NOT EXISTS "IX_StockTransactions_TransactionType" ON "StockTransactions" ("TransactionType");
CREATE INDEX IF NOT EXISTS "IX_StockTransactions_RelatedInventoryId" ON "StockTransactions" ("RelatedInventoryId");
