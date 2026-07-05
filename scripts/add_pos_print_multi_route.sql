-- Cho phép nhiều máy in cho cùng loại chứng từ (in đa máy)
ALTER TABLE "PosPrinterDocumentRoutes"
    DROP CONSTRAINT IF EXISTS "PosPrinterDocumentRoutes_StoreId_DocumentType_key";

DROP INDEX IF EXISTS "IX_PosPrinterDocumentRoutes_StoreId_DocumentType";

CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosPrinterDocumentRoutes_StoreId_DocumentType_PrinterId"
    ON "PosPrinterDocumentRoutes" ("StoreId", "DocumentType", "PrinterId");
