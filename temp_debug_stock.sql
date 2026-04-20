-- Check inventory items
SELECT i."Id", i."InventoryCode", i."Status", i."EndDate" 
FROM "AssetInventories" i ORDER BY i."CreatedAt" DESC LIMIT 5;

-- Check inventory items detail
SELECT ii."AssetId", ii."ExpectedQuantity", ii."ActualQuantity", ii."IsChecked", ii."Notes"
FROM "AssetInventoryItems" ii 
JOIN "AssetInventories" i ON ii."InventoryId" = i."Id"
ORDER BY i."CreatedAt" DESC LIMIT 20;

-- Check assets quantities
SELECT "Id", "Name", "AssetCode", "Quantity", "IsActive" FROM "Assets" WHERE "IsActive" = true ORDER BY "Name" LIMIT 20;

-- Check stock transactions
SELECT t."TransactionType", t."Quantity", t."BalanceAfter", t."Reason", t."Notes", t."TransactionDate", a."Name"
FROM "StockTransactions" t
JOIN "Assets" a ON a."Id" = t."AssetId"
ORDER BY t."TransactionDate" DESC LIMIT 20;
