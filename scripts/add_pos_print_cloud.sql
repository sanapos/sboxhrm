-- POS cloud print: máy in cửa hàng, routing, agent, job queue
-- Chạy trên PostgreSQL production sau deploy API

CREATE TABLE IF NOT EXISTS "PosStorePrinters" (
    "Id" uuid PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "Name" varchar(120) NOT NULL,
    "ConnectionType" integer NOT NULL DEFAULT 1,
    "PrinterBrand" varchar(32),
    "PaperSize" varchar(16) NOT NULL DEFAULT 'K80',
    "TextMode" varchar(32),
    "BluetoothAddress" varchar(64),
    "BluetoothName" varchar(120),
    "LanHost" varchar(64),
    "LanPort" integer NOT NULL DEFAULT 9100,
    "UsbDeviceName" varchar(120),
    "FeedBeforeCut" integer NOT NULL DEFAULT 8,
    "PartialCut" boolean NOT NULL DEFAULT true,
    "IsDefault" boolean NOT NULL DEFAULT false,
    "HealthStatus" integer NOT NULL DEFAULT 0,
    "LastSeenAt" timestamptz,
    "LastErrorMessage" varchar(500),
    "RequiresAgent" boolean NOT NULL DEFAULT false,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamptz NOT NULL DEFAULT now(),
    "CreatedBy" varchar(450),
    "UpdatedAt" timestamptz,
    "UpdatedBy" varchar(450),
    "LastModified" timestamptz,
    "LastModifiedBy" varchar(450),
    "Deleted" timestamptz,
    "DeletedBy" varchar(450)
);
CREATE INDEX IF NOT EXISTS "IX_PosStorePrinters_StoreId_IsDefault" ON "PosStorePrinters" ("StoreId", "IsDefault");
CREATE INDEX IF NOT EXISTS "IX_PosStorePrinters_StoreId_Name" ON "PosStorePrinters" ("StoreId", "Name");

CREATE TABLE IF NOT EXISTS "PosPrinterDocumentRoutes" (
    "Id" uuid PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "PrinterId" uuid NOT NULL REFERENCES "PosStorePrinters"("Id") ON DELETE CASCADE,
    "DocumentType" integer NOT NULL,
    "DefaultCopies" integer NOT NULL DEFAULT 1,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamptz NOT NULL DEFAULT now(),
    "CreatedBy" varchar(450),
    "UpdatedAt" timestamptz,
    "UpdatedBy" varchar(450),
    "LastModified" timestamptz,
    "LastModifiedBy" varchar(450),
    "Deleted" timestamptz,
    "DeletedBy" varchar(450),
    UNIQUE ("StoreId", "DocumentType")
);

CREATE TABLE IF NOT EXISTS "PosPrintAgents" (
    "Id" uuid PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "DeviceId" varchar(128) NOT NULL,
    "DeviceName" varchar(200),
    "EmployeeName" varchar(200),
    "UserId" varchar(450),
    "AssignedPrinterIdsJson" text NOT NULL DEFAULT '[]',
    "IsOnline" boolean NOT NULL DEFAULT false,
    "LastHeartbeatAt" timestamptz,
    "AppVersion" varchar(32),
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamptz NOT NULL DEFAULT now(),
    "CreatedBy" varchar(450),
    "UpdatedAt" timestamptz,
    "UpdatedBy" varchar(450),
    "LastModified" timestamptz,
    "LastModifiedBy" varchar(450),
    "Deleted" timestamptz,
    "DeletedBy" varchar(450),
    UNIQUE ("StoreId", "DeviceId")
);

CREATE TABLE IF NOT EXISTS "PosPrintJobs" (
    "Id" uuid PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "PrinterId" uuid NOT NULL REFERENCES "PosStorePrinters"("Id") ON DELETE RESTRICT,
    "AgentId" uuid REFERENCES "PosPrintAgents"("Id") ON DELETE SET NULL,
    "DocumentType" integer NOT NULL,
    "ReferenceNo" varchar(64),
    "ReferenceId" uuid,
    "PayloadFormat" integer NOT NULL DEFAULT 0,
    "Payload" text NOT NULL,
    "Copies" integer NOT NULL DEFAULT 1,
    "Status" integer NOT NULL DEFAULT 0,
    "RequestedByUserId" varchar(450),
    "RequestedByName" varchar(200),
    "ClaimedAt" timestamptz,
    "StartedAt" timestamptz,
    "CompletedAt" timestamptz,
    "ErrorCode" varchar(64),
    "ErrorMessage" varchar(500),
    "AttemptCount" integer NOT NULL DEFAULT 0,
    "ExpiresAt" timestamptz NOT NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamptz NOT NULL DEFAULT now(),
    "CreatedBy" varchar(450),
    "UpdatedAt" timestamptz,
    "UpdatedBy" varchar(450),
    "LastModified" timestamptz,
    "LastModifiedBy" varchar(450),
    "Deleted" timestamptz,
    "DeletedBy" varchar(450)
);
CREATE INDEX IF NOT EXISTS "IX_PosPrintJobs_Store_Status" ON "PosPrintJobs" ("StoreId", "Status", "CreatedAt");
CREATE INDEX IF NOT EXISTS "IX_PosPrintJobs_Printer_Status" ON "PosPrintJobs" ("PrinterId", "Status");
