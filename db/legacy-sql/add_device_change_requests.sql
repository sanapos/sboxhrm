-- Create DeviceChangeRequests table for mobile attendance device change approval flow
CREATE TABLE IF NOT EXISTS "DeviceChangeRequests" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "EmployeeId" character varying(100) NOT NULL,
    "EmployeeName" character varying(200) NOT NULL DEFAULT '',
    "OldDeviceRecordId" uuid NOT NULL,
    "OldDeviceName" character varying(200) NOT NULL DEFAULT '',
    "OldDeviceModel" character varying(200) NOT NULL DEFAULT '',
    "NewDeviceId" character varying(200) NOT NULL,
    "NewDeviceName" character varying(200) NOT NULL,
    "NewDeviceModel" character varying(200) NOT NULL DEFAULT '',
    "NewOsVersion" character varying(50),
    "NewWifiBssid" character varying(50),
    "NewFaceImagesJson" text NOT NULL DEFAULT '[]',
    "Status" integer NOT NULL DEFAULT 0,
    "Reason" character varying(500),
    "RequestedAt" timestamp with time zone NOT NULL DEFAULT now(),
    "ApprovedBy" uuid,
    "ApprovedAt" timestamp with time zone,
    "RejectReason" character varying(500),
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT now(),
    "CreatedBy" character varying(200),
    "UpdatedAt" timestamp with time zone,
    "UpdatedBy" character varying(200),
    "Deleted" timestamp with time zone,
    "DeletedBy" character varying(200),
    CONSTRAINT "PK_DeviceChangeRequests" PRIMARY KEY ("Id")
);

CREATE INDEX IF NOT EXISTS "IX_DeviceChangeRequests_StoreId_EmployeeId_Status" 
    ON "DeviceChangeRequests" ("StoreId", "EmployeeId", "Status") 
    WHERE "Deleted" IS NULL;

CREATE INDEX IF NOT EXISTS "IX_DeviceChangeRequests_StoreId_Status" 
    ON "DeviceChangeRequests" ("StoreId", "Status") 
    WHERE "Deleted" IS NULL;
