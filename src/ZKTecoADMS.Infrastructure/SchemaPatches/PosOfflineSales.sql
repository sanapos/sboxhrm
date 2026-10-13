-- Bán offline khi mất mạng: số hóa đơn offline cấp trước + lịch sử cài app (chống gian lận).
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "OfflineNo" character varying(40) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "OfflineAt" timestamp with time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "OfflineDeviceKey" character varying(128) NULL;

CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosSaleOrders_Store_OfflineNo"
    ON "PosSaleOrders" ("StoreId", "OfflineNo")
    WHERE "OfflineNo" IS NOT NULL AND "Deleted" IS NULL;

CREATE TABLE IF NOT EXISTS "PosDeviceInstalls" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "DeviceKey" character varying(128) NOT NULL,
    "InstallId" character varying(64) NOT NULL,
    "DeviceName" character varying(200) NULL,
    "Platform" character varying(16) NULL,
    "AppVersion" character varying(32) NULL,
    "OsFirstInstallAt" timestamp with time zone NULL,
    "FirstSeenAt" timestamp with time zone NOT NULL,
    "LastSeenAt" timestamp with time zone NOT NULL,
    "LastUserName" character varying(200) NULL,
    "PendingOfflineSales" integer NOT NULL DEFAULT 0,
    "LastOfflineSeq" integer NULL,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp with time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosDeviceInstalls_Store_Device_Install"
    ON "PosDeviceInstalls" ("StoreId", "DeviceKey", "InstallId");

CREATE TABLE IF NOT EXISTS "PosOfflineSerialBlocks" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "DeviceKey" character varying(128) NOT NULL,
    "InstallId" character varying(64) NOT NULL,
    "DeviceName" character varying(200) NULL,
    "FromSeq" integer NOT NULL,
    "ToSeq" integer NOT NULL,
    "ReservedBy" character varying(200) NULL,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp with time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosOfflineSerialBlocks_Store" ON "PosOfflineSerialBlocks" ("StoreId", "ToSeq");
