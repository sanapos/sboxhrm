-- Phase 1: nhân viên theo vị trí chấm công mobile
ALTER TABLE "AuthorizedMobileDevices"
    ADD COLUMN IF NOT EXISTS "SelectedLocationIdsJson" character varying(4000);

CREATE TABLE IF NOT EXISTS "MobileLocationEmployees" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "WorkLocationId" uuid NOT NULL,
    "EmployeeId" character varying(100) NOT NULL,
    "EmployeeName" character varying(200),
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_MobileLocationEmployees" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MobileLocationEmployees_Stores_StoreId"
        FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_MobileLocationEmployees_MobileWorkLocations_WorkLocationId"
        FOREIGN KEY ("WorkLocationId") REFERENCES "MobileWorkLocations" ("Id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_MobileLocationEmployees_StoreId_WorkLocationId_EmployeeId"
    ON "MobileLocationEmployees" ("StoreId", "WorkLocationId", "EmployeeId")
    WHERE "Deleted" IS NULL;

CREATE INDEX IF NOT EXISTS "IX_MobileLocationEmployees_StoreId_EmployeeId"
    ON "MobileLocationEmployees" ("StoreId", "EmployeeId");

CREATE INDEX IF NOT EXISTS "IX_MobileLocationEmployees_WorkLocationId"
    ON "MobileLocationEmployees" ("WorkLocationId");
