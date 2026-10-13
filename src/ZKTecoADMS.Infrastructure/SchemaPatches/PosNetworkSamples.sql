-- Số liệu mạng của thiết bị POS theo khung 5 phút — báo cáo «Mạng cửa hàng».
CREATE TABLE IF NOT EXISTS "PosNetworkSamples" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "DeviceId" character varying(128) NOT NULL,
    "DeviceName" character varying(200) NULL,
    "Platform" character varying(16) NULL,
    "AppVersion" character varying(32) NULL,
    "IsAgent" boolean NOT NULL DEFAULT false,
    "BucketStart" timestamp with time zone NOT NULL,
    "ConnType" character varying(16) NULL,
    "WifiRssi" integer NULL,
    "ApiCalls" integer NOT NULL DEFAULT 0,
    "ApiErrors" integer NOT NULL DEFAULT 0,
    "ApiTimeouts" integer NOT NULL DEFAULT 0,
    "PingSent" integer NOT NULL DEFAULT 0,
    "PingFailed" integer NOT NULL DEFAULT 0,
    "PingP50Ms" integer NULL,
    "PingP95Ms" integer NULL,
    "PingMaxMs" integer NULL,
    "OfflineSec" integer NOT NULL DEFAULT 0,
    "RealtimeDisconnects" integer NOT NULL DEFAULT 0,
    "RealtimeDownSec" integer NOT NULL DEFAULT 0,
    "PrinterChecks" integer NOT NULL DEFAULT 0,
    "PrinterFailed" integer NOT NULL DEFAULT 0,
    "PrinterAvgMs" integer NULL,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp with time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosNetworkSamples_Store_Device_Bucket"
    ON "PosNetworkSamples" ("StoreId", "DeviceId", "BucketStart");

CREATE INDEX IF NOT EXISTS "IX_PosNetworkSamples_Store_Bucket"
    ON "PosNetworkSamples" ("StoreId", "BucketStart");
