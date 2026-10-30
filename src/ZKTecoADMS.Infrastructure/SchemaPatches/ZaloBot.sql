-- Zalo bot của cửa hàng: thiết lập, liên kết tài khoản ↔ chat Zalo, hàng đợi tin gửi đi
CREATE TABLE IF NOT EXISTS "ZaloBotSettings" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "Enabled" boolean NOT NULL DEFAULT FALSE,
    "BotTokenEnc" character varying(1000) NULL,
    "BotId" character varying(100) NULL,
    "BotName" character varying(200) NULL,
    "BotLink" character varying(500) NULL,
    "WebhookSecret" character varying(100) NOT NULL DEFAULT '',
    "WebhookOk" boolean NOT NULL DEFAULT FALSE,
    "Categories" character varying(500) NOT NULL DEFAULT '',
    "HideMoney" boolean NOT NULL DEFAULT FALSE,
    "LastError" character varying(500) NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_ZaloBotSettings_Store" ON "ZaloBotSettings" ("StoreId");

CREATE TABLE IF NOT EXISTS "ZaloBotLinks" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "UserId" uuid NOT NULL,
    "ChatId" character varying(100) NULL,
    "ZaloName" character varying(200) NULL,
    "LinkedAt" timestamp without time zone NULL,
    "PendingCode" character varying(10) NULL,
    "PendingCodeExpiresAt" timestamp without time zone NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_ZaloBotLinks_Store_User" ON "ZaloBotLinks" ("StoreId", "UserId");
CREATE INDEX IF NOT EXISTS "IX_ZaloBotLinks_Store_Chat" ON "ZaloBotLinks" ("StoreId", "ChatId");
CREATE INDEX IF NOT EXISTS "IX_ZaloBotLinks_Store_Code" ON "ZaloBotLinks" ("StoreId", "PendingCode");

CREATE TABLE IF NOT EXISTS "ZaloBotMessages" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "UserId" uuid NULL,
    "ChatId" character varying(100) NOT NULL,
    "Text" text NOT NULL DEFAULT '',
    "NotificationId" uuid NULL,
    "CategoryCode" character varying(50) NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "Attempts" integer NOT NULL DEFAULT 0,
    "NextAttemptAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "SentAt" timestamp without time zone NULL,
    "Error" character varying(500) NULL
);
CREATE INDEX IF NOT EXISTS "IX_ZaloBotMessages_Status_Next" ON "ZaloBotMessages" ("Status", "NextAttemptAt");
CREATE INDEX IF NOT EXISTS "IX_ZaloBotMessages_Store_Created" ON "ZaloBotMessages" ("StoreId", "CreatedAt");
