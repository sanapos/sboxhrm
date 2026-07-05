-- Gán máy in theo sản phẩm / nhóm hàng POS
ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "DefaultPrinterId" uuid NULL
        REFERENCES "PosStorePrinters"("Id") ON DELETE SET NULL;

ALTER TABLE "PosProductCategories"
    ADD COLUMN IF NOT EXISTS "DefaultPrinterId" uuid NULL
        REFERENCES "PosStorePrinters"("Id") ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS "IX_PosProducts_StoreId_DefaultPrinterId"
    ON "PosProducts" ("StoreId", "DefaultPrinterId");

CREATE INDEX IF NOT EXISTS "IX_PosProductCategories_StoreId_DefaultPrinterId"
    ON "PosProductCategories" ("StoreId", "DefaultPrinterId");
