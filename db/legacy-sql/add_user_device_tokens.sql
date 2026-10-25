-- Migration: create UserDeviceTokens table for FCM push notifications.
-- Idempotent: safe to run multiple times.

CREATE TABLE IF NOT EXISTS "UserDeviceTokens" (
    "Id"          uuid           NOT NULL,
    "UserId"      uuid           NOT NULL,
    "Token"       varchar(512)   NOT NULL,
    "Platform"    varchar(16)    NOT NULL,
    "DeviceName"  varchar(128)   NULL,
    "AppVersion"  varchar(32)    NULL,
    "LastUsedAt"  timestamptz    NULL,
    "IsDisabled"  boolean        NOT NULL DEFAULT FALSE,
    "CreatedAt"   timestamptz    NOT NULL DEFAULT NOW(),
    "UpdatedAt"   timestamptz    NULL,
    "CreatedBy"   varchar(256)   NULL,
    "UpdatedBy"   varchar(256)   NULL,
    CONSTRAINT "PK_UserDeviceTokens" PRIMARY KEY ("Id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "UX_UserDeviceTokens_Token"
    ON "UserDeviceTokens" ("Token");

CREATE INDEX IF NOT EXISTS "IX_UserDeviceTokens_UserId"
    ON "UserDeviceTokens" ("UserId");

CREATE INDEX IF NOT EXISTS "IX_UserDeviceTokens_User_Disabled"
    ON "UserDeviceTokens" ("UserId", "IsDisabled");
