-- Create UserDeviceTokens table (was missing — entity/configuration exist in code but
-- no migration was generated). Idempotent.

CREATE TABLE IF NOT EXISTS "UserDeviceTokens" (
    "Id" uuid NOT NULL,
    "UserId" uuid NOT NULL,
    "Token" varchar(512) NOT NULL,
    "Platform" varchar(16) NOT NULL,
    "DeviceName" varchar(128) NULL,
    "AppVersion" varchar(32) NULL,
    "LastUsedAt" timestamp without time zone NULL,
    "IsDisabled" boolean NOT NULL DEFAULT false,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    CONSTRAINT "PK_UserDeviceTokens" PRIMARY KEY ("Id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "UX_UserDeviceTokens_Token" ON "UserDeviceTokens" ("Token");
CREATE INDEX IF NOT EXISTS "IX_UserDeviceTokens_UserId" ON "UserDeviceTokens" ("UserId");
CREATE INDEX IF NOT EXISTS "IX_UserDeviceTokens_User_Disabled" ON "UserDeviceTokens" ("UserId", "IsDisabled");

SELECT 'UserDeviceTokens ready' AS status, count(*) AS row_count FROM "UserDeviceTokens";
