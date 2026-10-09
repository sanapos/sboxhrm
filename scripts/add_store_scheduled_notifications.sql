BEGIN;

-- Thông báo hẹn giờ
CREATE TABLE IF NOT EXISTS "StoreScheduledNotifications" (
    "Id" uuid NOT NULL,
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
    "CreatedByUserId" uuid NOT NULL,
    "SendAt" timestamp without time zone NOT NULL,
    "PayloadJson" text NOT NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "SentAt" timestamp without time zone NULL,
    "BatchId" uuid NULL,
    "Error" character varying(300) NULL,
    "Title" character varying(200) NULL,
    "RecipientCount" integer NOT NULL DEFAULT 0,
    CONSTRAINT "PK_StoreScheduledNotifications" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_StoreScheduledNotifications_Status_SendAt" ON "StoreScheduledNotifications" ("Status", "SendAt");
CREATE INDEX IF NOT EXISTS "IX_StoreScheduledNotifications_StoreId_CreatedByUserId" ON "StoreScheduledNotifications" ("StoreId", "CreatedByUserId");

COMMIT;
