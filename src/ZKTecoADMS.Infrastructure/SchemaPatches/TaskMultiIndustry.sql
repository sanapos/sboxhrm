-- Công việc đa ngành: biểu mẫu, khách hàng / chứng từ, GPS, khoán, ảnh lên Drive / máy chủ
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "FormSchema" text NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "FormValues" text NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "CustomerId" uuid NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "CustomerName" character varying(200) NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "CustomerPhone" character varying(30) NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "RelatedType" character varying(30) NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "RelatedId" uuid NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "RelatedLabel" character varying(200) NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "Latitude" double precision NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "Longitude" double precision NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "RequireCheckIn" boolean NOT NULL DEFAULT false;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "PieceRate" numeric(18,2) NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "PieceRateTransactionId" uuid NULL;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "ReworkCount" integer NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS "IX_WorkTasks_Customer" ON "WorkTasks" ("CustomerId");
CREATE INDEX IF NOT EXISTS "IX_WorkTasks_Related" ON "WorkTasks" ("RelatedType", "RelatedId");

ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "FormSchema" text NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "PieceRate" numeric(18,2) NULL;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "AssignOnShift" boolean NOT NULL DEFAULT false;
ALTER TABLE "TaskTemplates" ADD COLUMN IF NOT EXISTS "RequireCheckIn" boolean NOT NULL DEFAULT false;

ALTER TABLE "TaskAttachments" ADD COLUMN IF NOT EXISTS "Category" character varying(30) NULL;
ALTER TABLE "TaskAttachments" ADD COLUMN IF NOT EXISTS "ChecklistItemId" character varying(60) NULL;
ALTER TABLE "TaskAttachments" ADD COLUMN IF NOT EXISTS "Caption" character varying(300) NULL;
ALTER TABLE "TaskAttachments" ADD COLUMN IF NOT EXISTS "Latitude" double precision NULL;
ALTER TABLE "TaskAttachments" ADD COLUMN IF NOT EXISTS "Longitude" double precision NULL;
ALTER TABLE "TaskAttachments" ADD COLUMN IF NOT EXISTS "StorageKind" character varying(20) NULL;

CREATE TABLE IF NOT EXISTS "TaskTimeLogs" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "TaskId" uuid NOT NULL,
    "StoreId" uuid NOT NULL,
    "EmployeeId" uuid NULL,
    "UserId" uuid NOT NULL,
    "StartAt" timestamp without time zone NOT NULL,
    "EndAt" timestamp without time zone NULL,
    "StartLat" double precision NULL,
    "StartLng" double precision NULL,
    "StartDistanceM" integer NULL,
    "EndLat" double precision NULL,
    "EndLng" double precision NULL,
    "EndDistanceM" integer NULL,
    "Note" character varying(300) NULL
);
CREATE INDEX IF NOT EXISTS "IX_TaskTimeLogs_Task" ON "TaskTimeLogs" ("TaskId", "StartAt");

CREATE TABLE IF NOT EXISTS "TaskWorkspaceSettings" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "IndustryKey" character varying(40) NULL,
    "PhotoStorage" character varying(20) NOT NULL DEFAULT 'server',
    "DriveRefreshTokenEnc" text NULL,
    "DriveAccountEmail" character varying(200) NULL,
    "DriveRootFolderId" character varying(100) NULL,
    "DriveConnectedAt" timestamp without time zone NULL,
    "DriveLastError" character varying(500) NULL,
    "CheckInRadiusM" integer NOT NULL DEFAULT 300,
    "OnboardedAt" timestamp without time zone NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "UX_TaskWorkspaceSettings_Store" ON "TaskWorkspaceSettings" ("StoreId");
