-- Mẫu báo giá / hợp đồng riêng theo từng khách
CREATE TABLE IF NOT EXISTS "PosCustomerDocTemplates" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "CustomerId" uuid NULL,
    "CustomerPhone" character varying(20) NULL,
    "CustomerName" character varying(200) NULL,
    "Kind" integer NOT NULL DEFAULT 0,
    "HtmlContent" text NOT NULL DEFAULT '',
    "SourceDocumentId" uuid NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosCustomerDocTemplates_Customer" ON "PosCustomerDocTemplates" ("StoreId", "Kind", "CustomerId");
CREATE INDEX IF NOT EXISTS "IX_PosCustomerDocTemplates_Phone" ON "PosCustomerDocTemplates" ("StoreId", "Kind", "CustomerPhone");
