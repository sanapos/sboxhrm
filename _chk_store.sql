SELECT "StoreId", COUNT(*) AS cnt FROM "PosProducts" WHERE "Deleted" IS NULL GROUP BY "StoreId";

SELECT p."Id", p."Name", p."StoreId", p."DefaultPrinterId"
FROM "PosProducts" p
WHERE p."Deleted" IS NULL AND p."StoreId" = '3e8bfefb-d2d2-4514-bfcd-01c099eef481';

SELECT s."Id", s."Name" FROM "PosStores" s WHERE s."Deleted" IS NULL LIMIT 10;
