BEGIN;

-- PosWarrantyClaim: lịch sử tiếp nhận / xử lý bảo hành theo seri
CREATE TABLE IF NOT EXISTS "PosWarrantyClaims" (
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
    "RegistrationId" uuid NOT NULL REFERENCES "PosProductWarrantyRegistrations"("Id") ON DELETE CASCADE,
    "ClaimType" integer NOT NULL DEFAULT 1,
    "Status" integer NOT NULL DEFAULT 0,
    "ReceivedDate" timestamp without time zone NOT NULL DEFAULT NOW(),
    "ResolvedDate" timestamp without time zone NULL,
    "InWarranty" boolean NOT NULL DEFAULT true,
    "Description" character varying(1000) NULL,
    "Resolution" character varying(1000) NULL,
    "NewRegistrationId" uuid NULL,
    CONSTRAINT "PK_PosWarrantyClaims" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_PosWarrantyClaims_StoreId_RegistrationId" ON "PosWarrantyClaims" ("StoreId", "RegistrationId");
CREATE INDEX IF NOT EXISTS "IX_PosWarrantyClaims_StoreId_Status" ON "PosWarrantyClaims" ("StoreId", "Status");

COMMIT;
