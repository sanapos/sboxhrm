-- Hồ sơ ngành bán hàng + khu vực/bàn/phòng + dịch vụ theo giờ + gói buổi gym
BEGIN;

-- PosProducts: billing / session pack
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "ServiceBillingMode" integer NOT NULL DEFAULT 0;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "MinBillMinutes" integer NULL;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "BillRoundMinutes" integer NULL;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "DefaultDurationMinutes" integer NULL;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "SessionPackCount" integer NOT NULL DEFAULT 0;

-- PosSaleOrders: resource / session time
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "ServiceResourceId" uuid NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "ResourceSessionId" uuid NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "ServiceStartedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "ServiceEndedAt" timestamp without time zone NULL;

-- PosSaleOrderLines: duration / assignee
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "DurationMinutes" integer NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "BillableMinutes" integer NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "ServiceStartedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "ServiceEndedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrderLines" ADD COLUMN IF NOT EXISTS "AssignedEmployeeId" uuid NULL;

CREATE TABLE IF NOT EXISTS "PosStoreSellSettings" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "SellProfile" integer NOT NULL DEFAULT 0,
    "DefaultSellMode" character varying(20) NOT NULL DEFAULT 'quick',
    "EnableResources" boolean NOT NULL DEFAULT false,
    "EnableHourlyBilling" boolean NOT NULL DEFAULT false,
    "EnableSessionPacks" boolean NOT NULL DEFAULT false,
    "RequireResourceOnSale" boolean NOT NULL DEFAULT false,
    "ShowFloorPlan" boolean NOT NULL DEFAULT false,
    "ExtraJson" character varying(4000) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosStoreSellSettings_StoreId"
    ON "PosStoreSellSettings" ("StoreId") WHERE "Deleted" IS NULL;

CREATE TABLE IF NOT EXISTS "PosServiceAreas" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "Name" character varying(100) NOT NULL,
    "Code" character varying(50) NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "AreaType" character varying(50) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosServiceAreas_StoreId_Name"
    ON "PosServiceAreas" ("StoreId", "Name") WHERE "Deleted" IS NULL;

CREATE TABLE IF NOT EXISTS "PosServiceResources" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "AreaId" uuid NOT NULL REFERENCES "PosServiceAreas"("Id") ON DELETE CASCADE,
    "Code" character varying(50) NOT NULL,
    "Name" character varying(100) NOT NULL,
    "ResourceKind" integer NOT NULL DEFAULT 1,
    "Capacity" integer NOT NULL DEFAULT 1,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "DefaultHourlyRate" numeric(18,2) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosServiceResources_StoreId_Code"
    ON "PosServiceResources" ("StoreId", "Code") WHERE "Deleted" IS NULL;

CREATE TABLE IF NOT EXISTS "PosResourceSessions" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "ResourceId" uuid NOT NULL REFERENCES "PosServiceResources"("Id") ON DELETE RESTRICT,
    "SaleOrderId" uuid NULL,
    "CustomerId" uuid NULL,
    "StartedAt" timestamp without time zone NOT NULL,
    "EndedAt" timestamp without time zone NULL,
    "PausedAt" timestamp without time zone NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "Note" character varying(500) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosResourceSessions_Store_Resource_Status"
    ON "PosResourceSessions" ("StoreId", "ResourceId", "Status") WHERE "Deleted" IS NULL;

CREATE TABLE IF NOT EXISTS "PosCustomerSessionBalances" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "CustomerId" uuid NOT NULL REFERENCES "PosCustomers"("Id") ON DELETE CASCADE,
    "ProductId" uuid NULL,
    "PackageName" character varying(200) NOT NULL DEFAULT '',
    "TotalSessions" integer NOT NULL DEFAULT 0,
    "RemainingSessions" integer NOT NULL DEFAULT 0,
    "ExpiresAt" timestamp without time zone NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosCustomerSessionBalances_Store_Customer"
    ON "PosCustomerSessionBalances" ("StoreId", "CustomerId") WHERE "Deleted" IS NULL;

CREATE TABLE IF NOT EXISTS "PosCustomerSessionTransactions" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "BalanceId" uuid NOT NULL REFERENCES "PosCustomerSessionBalances"("Id") ON DELETE CASCADE,
    "CustomerId" uuid NULL,
    "SaleOrderId" uuid NULL,
    "TransactionType" integer NOT NULL DEFAULT 0,
    "SessionDelta" integer NOT NULL DEFAULT 0,
    "RemainingAfter" integer NOT NULL DEFAULT 0,
    "Note" character varying(500) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosCustomerSessionTransactions_Store_Balance"
    ON "PosCustomerSessionTransactions" ("StoreId", "BalanceId") WHERE "Deleted" IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosSaleOrders_ServiceResourceId'
  ) THEN
    ALTER TABLE "PosSaleOrders"
      ADD CONSTRAINT "FK_PosSaleOrders_ServiceResourceId"
      FOREIGN KEY ("ServiceResourceId") REFERENCES "PosServiceResources"("Id") ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosSaleOrders_ResourceSessionId'
  ) THEN
    ALTER TABLE "PosSaleOrders"
      ADD CONSTRAINT "FK_PosSaleOrders_ResourceSessionId"
      FOREIGN KEY ("ResourceSessionId") REFERENCES "PosResourceSessions"("Id") ON DELETE SET NULL;
  END IF;
END $$;

COMMIT;
