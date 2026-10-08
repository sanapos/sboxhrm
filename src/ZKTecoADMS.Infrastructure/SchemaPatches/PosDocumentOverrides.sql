-- Sửa riêng từng chứng từ / hóa đơn mà không đụng mẫu in chung
ALTER TABLE "PosQuoteDocuments" ADD COLUMN IF NOT EXISTS "IsCustomWording" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosQuoteDocuments" ADD COLUMN IF NOT EXISTS "WordingUpdatedAt" timestamp without time zone NULL;
ALTER TABLE "PosQuoteDocuments" ADD COLUMN IF NOT EXISTS "WordingUpdatedBy" character varying(200) NULL;
ALTER TABLE "PosQuoteDocuments" ADD COLUMN IF NOT EXISTS "SourceHash" character varying(64) NULL;
-- Bản sửa lời văn cũ đánh dấu bằng comment trong HTML → chuyển sang cờ
UPDATE "PosQuoteDocuments" SET "IsCustomWording" = true
WHERE "IsCustomWording" = false AND "HtmlContent" LIKE '%<!--SBOX_DOC_WORDING-->%';

CREATE TABLE IF NOT EXISTS "PosQuoteDocumentRevisions" (
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
    "DocumentId" uuid NOT NULL,
    "HtmlContent" text NOT NULL DEFAULT '',
    "IsCustomWording" boolean NOT NULL DEFAULT false,
    "PrintTemplateId" uuid NULL,
    "Reason" character varying(30) NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS "IX_PosQuoteDocumentRevisions_Doc" ON "PosQuoteDocumentRevisions" ("DocumentId", "CreatedAt");

ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "PrintTemplateId" uuid NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "PrintNote" character varying(1000) NULL;
