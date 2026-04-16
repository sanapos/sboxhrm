-- Migration: Add Mobile Attendance tables
-- Date: 2026-04-02

-- 1. Mobile Attendance Settings (per store)
CREATE TABLE IF NOT EXISTS "MobileAttendanceSettings" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "EnableFaceId" boolean NOT NULL DEFAULT true,
    "EnableGps" boolean NOT NULL DEFAULT true,
    "RequireBothFaceAndGps" boolean NOT NULL DEFAULT true,
    "EnableLivenessDetection" boolean NOT NULL DEFAULT true,
    "GpsRadiusMeters" integer NOT NULL DEFAULT 100,
    "MinFaceMatchScore" double precision NOT NULL DEFAULT 80.0,
    "AutoApproveInRange" boolean NOT NULL DEFAULT true,
    "AllowManualApproval" boolean NOT NULL DEFAULT true,
    "MaxPhotosPerRegistration" integer NOT NULL DEFAULT 5,
    "MaxPunchesPerDay" integer NOT NULL DEFAULT 4,
    "RequirePhotoProof" boolean NOT NULL DEFAULT false,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_MobileAttendanceSettings" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MobileAttendanceSettings_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_MobileAttendanceSettings_StoreId" ON "MobileAttendanceSettings" ("StoreId");

-- 2. Mobile Work Locations
CREATE TABLE IF NOT EXISTS "MobileWorkLocations" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "Name" character varying(200) NOT NULL,
    "Address" character varying(500) NOT NULL DEFAULT '',
    "Latitude" double precision NOT NULL,
    "Longitude" double precision NOT NULL,
    "Radius" integer NOT NULL DEFAULT 100,
    "AutoApproveInRange" boolean NOT NULL DEFAULT true,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_MobileWorkLocations" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MobileWorkLocations_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_MobileWorkLocations_StoreId" ON "MobileWorkLocations" ("StoreId");

-- 3. Mobile Face Registrations
CREATE TABLE IF NOT EXISTS "MobileFaceRegistrations" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "OdooEmployeeId" character varying(100) NOT NULL,
    "EmployeeName" character varying(200) NOT NULL,
    "EmployeeCode" character varying(50),
    "Department" character varying(200),
    "FaceImagesJson" text NOT NULL DEFAULT '[]',
    "IsVerified" boolean NOT NULL DEFAULT false,
    "RegisteredAt" timestamp without time zone,
    "LastVerifiedAt" timestamp without time zone,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_MobileFaceRegistrations" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MobileFaceRegistrations_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_MobileFaceRegistrations_StoreId" ON "MobileFaceRegistrations" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_MobileFaceRegistrations_OdooEmployeeId" ON "MobileFaceRegistrations" ("OdooEmployeeId");

-- 4. Authorized Mobile Devices
CREATE TABLE IF NOT EXISTS "AuthorizedMobileDevices" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "DeviceId" character varying(200) NOT NULL,
    "DeviceName" character varying(200) NOT NULL,
    "DeviceModel" character varying(200) NOT NULL,
    "OsVersion" character varying(50),
    "EmployeeId" character varying(100),
    "EmployeeName" character varying(200),
    "IsAuthorized" boolean NOT NULL DEFAULT true,
    "CanUseFaceId" boolean NOT NULL DEFAULT true,
    "CanUseGps" boolean NOT NULL DEFAULT true,
    "AuthorizedAt" timestamp without time zone,
    "LastUsedAt" timestamp without time zone,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_AuthorizedMobileDevices" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_AuthorizedMobileDevices_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_AuthorizedMobileDevices_StoreId" ON "AuthorizedMobileDevices" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_AuthorizedMobileDevices_DeviceId" ON "AuthorizedMobileDevices" ("DeviceId");

-- 5. Mobile Attendance Records
CREATE TABLE IF NOT EXISTS "MobileAttendanceRecords" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "OdooEmployeeId" character varying(100) NOT NULL,
    "EmployeeName" character varying(200) NOT NULL,
    "PunchTime" timestamp without time zone NOT NULL DEFAULT NOW(),
    "PunchType" integer NOT NULL DEFAULT 0,
    "Latitude" double precision,
    "Longitude" double precision,
    "LocationName" character varying(200),
    "DistanceFromLocation" double precision,
    "FaceImageUrl" character varying(500),
    "FaceMatchScore" double precision,
    "VerifyMethod" character varying(20) NOT NULL DEFAULT 'face_gps',
    "Status" character varying(20) NOT NULL DEFAULT 'pending',
    "ApprovedBy" character varying(200),
    "ApprovedAt" timestamp without time zone,
    "RejectReason" character varying(500),
    "DeviceId" character varying(200),
    "DeviceName" character varying(200),
    "Note" character varying(500),
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_MobileAttendanceRecords" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MobileAttendanceRecords_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_MobileAttendanceRecords_StoreId" ON "MobileAttendanceRecords" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_MobileAttendanceRecords_OdooEmployeeId" ON "MobileAttendanceRecords" ("OdooEmployeeId");
CREATE INDEX IF NOT EXISTS "IX_MobileAttendanceRecords_PunchTime" ON "MobileAttendanceRecords" ("PunchTime");
CREATE INDEX IF NOT EXISTS "IX_MobileAttendanceRecords_Status" ON "MobileAttendanceRecords" ("Status");
