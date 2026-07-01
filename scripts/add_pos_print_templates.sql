CREATE TABLE IF NOT EXISTS "PosPrintTemplates" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "Name" varchar(120) NOT NULL,
    "DocumentType" integer NOT NULL DEFAULT 1,
    "PaperSize" integer NOT NULL DEFAULT 1,
    "HtmlContent" text NOT NULL DEFAULT '',
    "IsDefault" boolean NOT NULL DEFAULT false,
    "IsActive" boolean NOT NULL DEFAULT true,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" varchar(256) NULL,
    "UpdatedAt" timestamp with time zone NULL,
    "UpdatedBy" varchar(256) NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp with time zone NULL,
    "DeletedBy" varchar(256) NULL,
    CONSTRAINT "FK_PosPrintTemplates_Stores_StoreId"
        FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_PosPrintTemplates_StoreId_DocumentType_IsDefault"
    ON "PosPrintTemplates" ("StoreId", "DocumentType", "IsDefault");
CREATE INDEX IF NOT EXISTS "IX_PosPrintTemplates_StoreId_DocumentType_PaperSize_Name"
    ON "PosPrintTemplates" ("StoreId", "DocumentType", "PaperSize", "Name");
