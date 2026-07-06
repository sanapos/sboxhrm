-- =========================================================
-- apply_all_migrations.sql
-- Safe migration script: applies all pending EF migrations
-- using IF NOT EXISTS / IF EXISTS patterns.
-- Run: docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -f /tmp/apply_all_migrations.sql
-- =========================================================

BEGIN;

-- =========================================================
-- 20260325000000_AddContractEndDateToEmployees (if not already applied)
-- =========================================================
ALTER TABLE "Employees" ADD COLUMN IF NOT EXISTS "ContractEndDate" timestamp without time zone NULL;

-- =========================================================
-- 20260508104414_AddBranchPermissions
-- (large migration - apply structural parts only)
-- =========================================================

-- PlainTextPassword: Super Admin tra cứu mật khẩu (admin tạo/đặt lại)
ALTER TABLE "AspNetUsers" ADD COLUMN IF NOT EXISTS "PlainTextPassword" text;

-- Drop old unique indexes on Employees (will recreate non-unique below)
DROP INDEX IF EXISTS "IX_Employees_CompanyEmail";
DROP INDEX IF EXISTS "IX_Employees_EmployeeCode";

-- Add columns to TaskComments
ALTER TABLE "TaskComments" ADD COLUMN IF NOT EXISTS "CommentType" integer NOT NULL DEFAULT 0;
ALTER TABLE "TaskComments" ADD COLUMN IF NOT EXISTS "ImageUrls" character varying(4000);
ALTER TABLE "TaskComments" ADD COLUMN IF NOT EXISTS "LinkUrls" character varying(4000);
ALTER TABLE "TaskComments" ADD COLUMN IF NOT EXISTS "ProgressSnapshot" integer;

-- Add columns to ShiftTemplates (some may already be in bootstrap)
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "Code" text;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "EarlyCheckInMinutes" integer NOT NULL DEFAULT 0;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "EarlyLeaveGraceMinutes" integer NOT NULL DEFAULT 0;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "LateGraceMinutes" integer NOT NULL DEFAULT 0;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "OvernightCutoffTime" interval;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "OvertimeMinutesThreshold" integer NOT NULL DEFAULT 0;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "ShiftType" text;
ALTER TABLE "ShiftTemplates" ADD COLUMN IF NOT EXISTS "Description" text;

-- Drop old FK on ShiftTemplates.StoreId and ManagerId (non-nullable -> nullable or FK type change)
ALTER TABLE "ShiftTemplates" DROP CONSTRAINT IF EXISTS "FK_ShiftTemplates_AspNetUsers_ManagerId";
ALTER TABLE "ShiftTemplates" DROP CONSTRAINT IF EXISTS "FK_ShiftTemplates_Stores_StoreId";

-- Payslips new columns
ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "Allowances" numeric;
ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "HealthInsurance" numeric;
ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "SocialInsurance" numeric;
ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "Tax" numeric;
ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "UnemploymentInsurance" numeric;

-- Leaves approval columns
ALTER TABLE "Leaves" ADD COLUMN IF NOT EXISTS "CurrentApprovalStep" integer NOT NULL DEFAULT 0;
ALTER TABLE "Leaves" ADD COLUMN IF NOT EXISTS "TotalApprovalLevels" integer NOT NULL DEFAULT 0;

-- Devices DeviceType (may already be in bootstrap)
ALTER TABLE "Devices" ADD COLUMN IF NOT EXISTS "DeviceType" integer NOT NULL DEFAULT 0;

-- AttendanceLogs MobileAttendanceRecordId (may already be in bootstrap)
ALTER TABLE "AttendanceLogs" ADD COLUMN IF NOT EXISTS "MobileAttendanceRecordId" uuid;

-- AttendanceCorrectionRequests approval columns
ALTER TABLE "AttendanceCorrectionRequests" ADD COLUMN IF NOT EXISTS "CurrentApprovalStep" integer NOT NULL DEFAULT 0;
ALTER TABLE "AttendanceCorrectionRequests" ADD COLUMN IF NOT EXISTS "TotalApprovalLevels" integer NOT NULL DEFAULT 0;

-- Assets new columns
ALTER TABLE "Assets" ADD COLUMN IF NOT EXISTS "Color" text;
ALTER TABLE "Assets" ADD COLUMN IF NOT EXISTS "QrCode" text;
ALTER TABLE "Assets" ADD COLUMN IF NOT EXISTS "Size" text;

-- AssetInventoryItems
ALTER TABLE "AssetInventoryItems" ADD COLUMN IF NOT EXISTS "StoredExpectedQuantity" integer NOT NULL DEFAULT 0;

-- AdvanceRequests approval columns
ALTER TABLE "AdvanceRequests" ADD COLUMN IF NOT EXISTS "CurrentApprovalStep" integer NOT NULL DEFAULT 0;
ALTER TABLE "AdvanceRequests" ADD COLUMN IF NOT EXISTS "TotalApprovalLevels" integer NOT NULL DEFAULT 0;

-- AdvanceApprovalRecords table
CREATE TABLE IF NOT EXISTS "AdvanceApprovalRecords" (
    "Id" uuid NOT NULL,
    "AdvanceRequestId" uuid NOT NULL,
    "StepOrder" integer NOT NULL,
    "StepName" character varying(200),
    "AssignedUserId" uuid,
    "AssignedUserName" character varying(200),
    "ActualUserId" uuid,
    "ActualUserName" character varying(200),
    "Status" integer NOT NULL,
    "Note" character varying(1000),
    "ActionDate" timestamp without time zone,
    "StoreId" uuid,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_AdvanceApprovalRecords" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_AdvanceApprovalRecords_AdvanceRequests_AdvanceRequestId"
        FOREIGN KEY ("AdvanceRequestId") REFERENCES "AdvanceRequests" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_AdvanceApprovalRecords_AdvanceRequestId" ON "AdvanceApprovalRecords" ("AdvanceRequestId");
CREATE INDEX IF NOT EXISTS "IX_AdvanceApprovalRecords_ActualUserId" ON "AdvanceApprovalRecords" ("ActualUserId");
CREATE INDEX IF NOT EXISTS "IX_AdvanceApprovalRecords_AssignedUserId" ON "AdvanceApprovalRecords" ("AssignedUserId");

-- AppBugReports table
CREATE TABLE IF NOT EXISTS "AppBugReports" (
    "Id" uuid NOT NULL,
    "UserId" character varying(100),
    "UserName" character varying(200),
    "UserEmail" character varying(100),
    "StoreName" character varying(200),
    "Type" character varying(30) NOT NULL,
    "Title" character varying(300) NOT NULL,
    "Content" character varying(5000) NOT NULL,
    "AppVersion" character varying(50),
    "DeviceInfo" character varying(200),
    "Status" character varying(30) NOT NULL,
    "AdminNote" character varying(2000),
    "ResolvedAt" timestamp without time zone,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_AppBugReports" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_AppBugReports_Status" ON "AppBugReports" ("Status");

-- AppPages table
CREATE TABLE IF NOT EXISTS "AppPages" (
    "Id" uuid NOT NULL,
    "Type" character varying(30) NOT NULL,
    "Title" character varying(200) NOT NULL,
    "Content" character varying(100000),
    "IsPublished" boolean NOT NULL DEFAULT false,
    "UpdatedByName" character varying(200),
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_AppPages" PRIMARY KEY ("Id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_AppPages_Type" ON "AppPages" ("Type");

-- ApprovalRecords (for AttendanceCorrectionRequests)
CREATE TABLE IF NOT EXISTS "ApprovalRecords" (
    "Id" uuid NOT NULL,
    "CorrectionRequestId" uuid NOT NULL,
    "StepOrder" integer NOT NULL,
    "StepName" character varying(200),
    "AssignedUserId" uuid,
    "AssignedUserName" character varying(200),
    "ActualUserId" uuid,
    "ActualUserName" character varying(200),
    "Status" integer NOT NULL,
    "Note" character varying(1000),
    "ActionDate" timestamp without time zone,
    "StoreId" uuid,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_ApprovalRecords" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ApprovalRecords_AttendanceCorrectionRequests_CorrectionRequ~"
        FOREIGN KEY ("CorrectionRequestId") REFERENCES "AttendanceCorrectionRequests" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_ApprovalRecords_CorrectionRequestId" ON "ApprovalRecords" ("CorrectionRequestId");
CREATE INDEX IF NOT EXISTS "IX_ApprovalRecords_AssignedUserId" ON "ApprovalRecords" ("AssignedUserId");
CREATE INDEX IF NOT EXISTS "IX_ApprovalRecords_ActualUserId" ON "ApprovalRecords" ("ActualUserId");

-- BranchPermissions table
CREATE TABLE IF NOT EXISTS "BranchPermissions" (
    "Id" uuid NOT NULL,
    "UserId" uuid NOT NULL,
    "BranchId" uuid,
    "IncludeChildren" boolean NOT NULL DEFAULT false,
    "StoreId" uuid,
    "CanView" boolean NOT NULL DEFAULT false,
    "CanCreate" boolean NOT NULL DEFAULT false,
    "CanEdit" boolean NOT NULL DEFAULT false,
    "CanDelete" boolean NOT NULL DEFAULT false,
    "IsActive" boolean NOT NULL DEFAULT true,
    "GrantedBy" character varying(100),
    "Note" character varying(500),
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_BranchPermissions" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_BranchPermissions_AspNetUsers_UserId"
        FOREIGN KEY ("UserId") REFERENCES "AspNetUsers" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_BranchPermissions_UserId" ON "BranchPermissions" ("UserId");
CREATE INDEX IF NOT EXISTS "IX_BranchPermissions_StoreId" ON "BranchPermissions" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_BranchPermissions_BranchId" ON "BranchPermissions" ("BranchId");

-- DeviceChangeRequests table
CREATE TABLE IF NOT EXISTS "DeviceChangeRequests" (
    "Id" uuid NOT NULL,
    "StoreId" uuid NOT NULL,
    "EmployeeId" character varying(100) NOT NULL,
    "EmployeeName" character varying(200) NOT NULL,
    "OldDeviceRecordId" uuid NOT NULL,
    "OldDeviceName" character varying(200) NOT NULL,
    "OldDeviceModel" character varying(200) NOT NULL,
    "NewDeviceId" character varying(200) NOT NULL,
    "NewDeviceName" character varying(200) NOT NULL,
    "NewDeviceModel" character varying(200) NOT NULL,
    "NewOsVersion" character varying(50),
    "NewWifiBssid" character varying(50),
    "NewFaceImagesJson" text NOT NULL DEFAULT '[]',
    "Status" integer NOT NULL DEFAULT 0,
    "Reason" character varying(500),
    "RequestedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "ApprovedBy" uuid,
    "ApprovedAt" timestamp without time zone,
    "RejectReason" character varying(500),
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_DeviceChangeRequests" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_DeviceChangeRequests_Stores_StoreId"
        FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_DeviceChangeRequests_StoreId" ON "DeviceChangeRequests" ("StoreId");

-- EmployeeLiveLocations table
CREATE TABLE IF NOT EXISTS "EmployeeLiveLocations" (
    "Id" uuid NOT NULL,
    "StoreId" uuid NOT NULL,
    "EmployeeId" character varying(100) NOT NULL,
    "Latitude" double precision NOT NULL DEFAULT 0,
    "Longitude" double precision NOT NULL DEFAULT 0,
    "Accuracy" double precision,
    "UpdatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT "PK_EmployeeLiveLocations" PRIMARY KEY ("Id")
);
CREATE INDEX IF NOT EXISTS "IX_EmployeeLiveLocations_StoreId_EmployeeId" ON "EmployeeLiveLocations" ("StoreId", "EmployeeId");

-- FieldLocations table
CREATE TABLE IF NOT EXISTS "FieldLocations" (
    "Id" uuid NOT NULL,
    "StoreId" uuid NOT NULL,
    "Name" character varying(300) NOT NULL,
    "Address" character varying(500),
    "ContactName" character varying(200),
    "ContactPhone" character varying(50),
    "ContactEmail" character varying(200),
    "Note" character varying(1000),
    "Latitude" double precision NOT NULL DEFAULT 0,
    "Longitude" double precision NOT NULL DEFAULT 0,
    "Radius" integer NOT NULL DEFAULT 100,
    "PhotoUrlsJson" text,
    "RegisteredByEmployeeId" character varying(100),
    "RegisteredByEmployeeName" character varying(200),
    "Category" character varying(50),
    "IsApproved" boolean NOT NULL DEFAULT false,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_FieldLocations" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_FieldLocations_Stores_StoreId"
        FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_FieldLocations_StoreId" ON "FieldLocations" ("StoreId");

-- JourneyTrackings table
CREATE TABLE IF NOT EXISTS "JourneyTrackings" (
    "Id" uuid NOT NULL,
    "StoreId" uuid NOT NULL,
    "EmployeeId" character varying(100) NOT NULL,
    "EmployeeName" character varying(200) NOT NULL,
    "JourneyDate" timestamp without time zone NOT NULL,
    "StartTime" timestamp without time zone,
    "EndTime" timestamp without time zone,
    "Status" character varying(30) NOT NULL DEFAULT 'Active',
    "TotalDistanceKm" double precision NOT NULL DEFAULT 0,
    "TotalTravelMinutes" integer NOT NULL DEFAULT 0,
    "TotalOnSiteMinutes" integer NOT NULL DEFAULT 0,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_JourneyTrackings" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_JourneyTrackings_Stores_StoreId"
        FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_JourneyTrackings_StoreId" ON "JourneyTrackings" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_JourneyTrackings_EmployeeId" ON "JourneyTrackings" ("EmployeeId");

-- Recreate non-unique indexes on Employees
CREATE INDEX IF NOT EXISTS "IX_Employees_CompanyEmail" ON "Employees" ("CompanyEmail");
CREATE INDEX IF NOT EXISTS "IX_Employees_EmployeeCode" ON "Employees" ("EmployeeCode");

-- Re-add FKs to ShiftTemplates (that were dropped above) - safe with IF NOT EXISTS via DO
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'FK_ShiftTemplates_Stores_StoreId'
    ) THEN
        ALTER TABLE "ShiftTemplates"
            ADD CONSTRAINT "FK_ShiftTemplates_Stores_StoreId"
            FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'FK_ShiftTemplates_AspNetUsers_ManagerId'
    ) THEN
        ALTER TABLE "ShiftTemplates"
            ADD CONSTRAINT "FK_ShiftTemplates_AspNetUsers_ManagerId"
            FOREIGN KEY ("ManagerId") REFERENCES "AspNetUsers" ("Id");
    END IF;
END $$;

-- Re-add FKs to AssetInventories, Assets, AssetTransfers (if they were dropped)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'FK_AssetInventories_AspNetUsers_ResponsibleUserId'
    ) THEN
        ALTER TABLE "AssetInventories"
            ADD CONSTRAINT "FK_AssetInventories_AspNetUsers_ResponsibleUserId"
            FOREIGN KEY ("ResponsibleUserId") REFERENCES "AspNetUsers" ("Id");
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'FK_Assets_AspNetUsers_CurrentAssigneeId'
    ) THEN
        ALTER TABLE "Assets"
            ADD CONSTRAINT "FK_Assets_AspNetUsers_CurrentAssigneeId"
            FOREIGN KEY ("CurrentAssigneeId") REFERENCES "AspNetUsers" ("Id");
    END IF;
END $$;

-- =========================================================
-- 20260508152741_AddBranchIdToEmployee
-- =========================================================
-- Drop BranchId from Devices (if exists - bootstrap may have already done this)
ALTER TABLE "Devices" DROP CONSTRAINT IF EXISTS "FK_Devices_Branches_BranchId";
DROP INDEX IF EXISTS "IX_Devices_BranchId";
ALTER TABLE "Devices" DROP COLUMN IF EXISTS "BranchId";

-- Add BranchId to Employees
ALTER TABLE "Employees" ADD COLUMN IF NOT EXISTS "BranchId" uuid;
CREATE INDEX IF NOT EXISTS "IX_Employees_BranchId" ON "Employees" ("BranchId");
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'FK_Employees_Branches_BranchId'
    ) THEN
        ALTER TABLE "Employees"
            ADD CONSTRAINT "FK_Employees_Branches_BranchId"
            FOREIGN KEY ("BranchId") REFERENCES "Branches" ("Id") ON DELETE SET NULL;
    END IF;
END $$;

-- =========================================================
-- 20260525120000_RestoreWorkScheduleMultiShiftIndex
-- =========================================================
DROP INDEX IF EXISTS "IX_WorkSchedules_Employee_Date";
DROP INDEX IF EXISTS "IX_WorkSchedules_Employee_Date_Shift";
CREATE UNIQUE INDEX IF NOT EXISTS "IX_WorkSchedules_Employee_Date_Shift"
    ON "WorkSchedules" ("EmployeeId", "Date", "ShiftId");

-- =========================================================
-- 20260525140000_AddNewPunchTypeToAttendanceCorrection
-- (already applied manually - just ensure column exists)
-- =========================================================
ALTER TABLE "AttendanceCorrectionRequests" ADD COLUMN IF NOT EXISTS "NewPunchType" character varying(20);

-- =========================================================
-- 20260526054332_AddScheduleApprovalRecords
-- =========================================================
ALTER TABLE "ScheduleRegistrations" ADD COLUMN IF NOT EXISTS "CurrentApprovalStep" integer NOT NULL DEFAULT 0;
ALTER TABLE "ScheduleRegistrations" ADD COLUMN IF NOT EXISTS "TotalApprovalLevels" integer NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS "ScheduleApprovalRecords" (
    "Id" uuid NOT NULL,
    "ScheduleRegistrationId" uuid NOT NULL,
    "StepOrder" integer NOT NULL,
    "StepName" character varying(200),
    "AssignedUserId" uuid,
    "AssignedUserName" character varying(200),
    "ActualUserId" uuid,
    "ActualUserName" character varying(200),
    "Status" integer NOT NULL,
    "Note" character varying(1000),
    "ActionDate" timestamp without time zone,
    "StoreId" uuid,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_ScheduleApprovalRecords" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ScheduleApprovalRecords_ScheduleRegistrations_ScheduleRegis~"
        FOREIGN KEY ("ScheduleRegistrationId") REFERENCES "ScheduleRegistrations" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_ScheduleApprovalRecords_ScheduleRegistrationId" ON "ScheduleApprovalRecords" ("ScheduleRegistrationId");
CREATE INDEX IF NOT EXISTS "IX_ScheduleApprovalRecords_AssignedUserId" ON "ScheduleApprovalRecords" ("AssignedUserId");
CREATE INDEX IF NOT EXISTS "IX_ScheduleApprovalRecords_ActualUserId" ON "ScheduleApprovalRecords" ("ActualUserId");

-- =========================================================
-- 20260526120000_AddCommunicationPublicShare
-- =========================================================
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "IsPublicShareEnabled" boolean NOT NULL DEFAULT false;
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "PublicShareToken" character varying(64);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_InternalCommunications_PublicShareToken"
    ON "InternalCommunications" ("PublicShareToken")
    WHERE "PublicShareToken" IS NOT NULL;

-- =========================================================
-- 20260527120000_FixOrgAssignmentCareerHistoryIndex
-- =========================================================
DROP INDEX IF EXISTS "IX_OrgAssignments_Emp_Dept_Pos";
CREATE UNIQUE INDEX IF NOT EXISTS "IX_OrgAssignments_Emp_Dept_Pos_Active"
    ON "OrgAssignments" ("EmployeeId", "DepartmentId", "PositionId")
    WHERE "Deleted" IS NULL AND "EndDate" IS NULL;

-- =========================================================
-- 20260527140000_EnhanceTaskAssignment
-- =========================================================
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "BranchId" uuid;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "DepartmentId" uuid;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "TemplateId" uuid;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "SlaReminderHours" integer;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "AcceptedAt" timestamp without time zone;
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "RejectionReason" character varying(500);
ALTER TABLE "WorkTasks" ADD COLUMN IF NOT EXISTS "AssignmentNote" character varying(1000);

CREATE INDEX IF NOT EXISTS "IX_WorkTasks_BranchId" ON "WorkTasks" ("BranchId");
CREATE INDEX IF NOT EXISTS "IX_WorkTasks_DepartmentId" ON "WorkTasks" ("DepartmentId");
CREATE INDEX IF NOT EXISTS "IX_WorkTasks_TemplateId" ON "WorkTasks" ("TemplateId");

-- TaskTemplates table
CREATE TABLE IF NOT EXISTS "TaskTemplates" (
    "Id" uuid NOT NULL,
    "StoreId" uuid NOT NULL,
    "Name" character varying(120) NOT NULL,
    "Title" character varying(200) NOT NULL,
    "Description" character varying(2000),
    "TaskType" integer NOT NULL DEFAULT 0,
    "Priority" integer NOT NULL DEFAULT 0,
    "EstimatedHours" numeric,
    "DefaultSlaReminderHours" integer,
    "Tags" character varying(500),
    "Checklist" character varying(4000),
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" text,
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_TaskTemplates" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_TaskTemplates_Stores_StoreId"
        FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_TaskTemplates_StoreId" ON "TaskTemplates" ("StoreId");

-- TaskDependencies table
CREATE TABLE IF NOT EXISTS "TaskDependencies" (
    "Id" uuid NOT NULL,
    "TaskId" uuid NOT NULL,
    "DependsOnTaskId" uuid NOT NULL,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT "PK_TaskDependencies" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_TaskDependencies_WorkTasks_TaskId"
        FOREIGN KEY ("TaskId") REFERENCES "WorkTasks" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_TaskDependencies_WorkTasks_DependsOnTaskId"
        FOREIGN KEY ("DependsOnTaskId") REFERENCES "WorkTasks" ("Id") ON DELETE RESTRICT
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_TaskDependencies_TaskId_DependsOnTaskId"
    ON "TaskDependencies" ("TaskId", "DependsOnTaskId");
CREATE INDEX IF NOT EXISTS "IX_TaskDependencies_DependsOnTaskId" ON "TaskDependencies" ("DependsOnTaskId");

-- Add FKs for WorkTasks new columns
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'FK_WorkTasks_Branches_BranchId'
    ) THEN
        ALTER TABLE "WorkTasks"
            ADD CONSTRAINT "FK_WorkTasks_Branches_BranchId"
            FOREIGN KEY ("BranchId") REFERENCES "Branches" ("Id") ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'FK_WorkTasks_Departments_DepartmentId'
    ) THEN
        ALTER TABLE "WorkTasks"
            ADD CONSTRAINT "FK_WorkTasks_Departments_DepartmentId"
            FOREIGN KEY ("DepartmentId") REFERENCES "Departments" ("Id") ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'FK_WorkTasks_TaskTemplates_TemplateId'
    ) THEN
        ALTER TABLE "WorkTasks"
            ADD CONSTRAINT "FK_WorkTasks_TaskTemplates_TemplateId"
            FOREIGN KEY ("TemplateId") REFERENCES "TaskTemplates" ("Id") ON DELETE SET NULL;
    END IF;
END $$;

-- =========================================================
-- 20260528120000_ShiftSwapFkToShiftTemplate
-- =========================================================
DO $$
BEGIN
    -- Drop old FKs to Shifts
    ALTER TABLE "ShiftSwapRequests" DROP CONSTRAINT IF EXISTS "FK_ShiftSwapRequests_Shifts_RequesterShiftId";
    ALTER TABLE "ShiftSwapRequests" DROP CONSTRAINT IF EXISTS "FK_ShiftSwapRequests_Shifts_TargetShiftId";
    -- Drop new FKs to ShiftTemplates first (in case partial state)
    ALTER TABLE "ShiftSwapRequests" DROP CONSTRAINT IF EXISTS "FK_ShiftSwapRequests_ShiftTemplates_RequesterShiftId";
    ALTER TABLE "ShiftSwapRequests" DROP CONSTRAINT IF EXISTS "FK_ShiftSwapRequests_ShiftTemplates_TargetShiftId";

    -- Add new FKs to ShiftTemplates
    ALTER TABLE "ShiftSwapRequests"
        ADD CONSTRAINT "FK_ShiftSwapRequests_ShiftTemplates_RequesterShiftId"
        FOREIGN KEY ("RequesterShiftId") REFERENCES "ShiftTemplates" ("Id") ON DELETE RESTRICT;

    ALTER TABLE "ShiftSwapRequests"
        ADD CONSTRAINT "FK_ShiftSwapRequests_ShiftTemplates_TargetShiftId"
        FOREIGN KEY ("TargetShiftId") REFERENCES "ShiftTemplates" ("Id") ON DELETE RESTRICT;
END $$;

-- =========================================================
-- 20260528180000_AddAttendanceUniqueDevicePinTime
-- =========================================================
-- Remove duplicates first
DELETE FROM "AttendanceLogs" a
WHERE a."Id" IN (
    SELECT al."Id"
    FROM (
        SELECT "Id",
               ROW_NUMBER() OVER (
                   PARTITION BY "DeviceId", "PIN", "AttendanceTime"
                   ORDER BY "CreatedAt" ASC, "Id" ASC
               ) AS rn
        FROM "AttendanceLogs"
    ) al
    WHERE al.rn > 1
);
-- Create unique index
CREATE UNIQUE INDEX IF NOT EXISTS "UX_Attendance_Device_Pin_Time"
    ON "AttendanceLogs" ("DeviceId", "PIN", "AttendanceTime");

-- =========================================================
-- MaintenanceWindows table (created by add_maintenance_windows.sql)
-- =========================================================
CREATE TABLE IF NOT EXISTS "MaintenanceWindows" (
    "Id"                     uuid         NOT NULL PRIMARY KEY,
    "Title"                  varchar(200) NOT NULL,
    "Message"                text         NOT NULL,
    "StartAt"                timestamp    NOT NULL,
    "EndAt"                  timestamp    NOT NULL,
    "AffectedModulesJson"    jsonb        NULL,
    "IsActive"               boolean      NOT NULL DEFAULT false,
    "BlockAccess"            boolean      NOT NULL DEFAULT true,
    "NotifyBeforeMinutesCsv" varchar(100) NULL,
    "NotifiedMinutesCsv"     varchar(100) NULL,
    "StartNotified"          boolean      NOT NULL DEFAULT false,
    "EndNotified"            boolean      NOT NULL DEFAULT false,
    "CreatedByUserId"        uuid         NOT NULL,
    "CreatedAt"              timestamp    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "CreatedBy"              text         NULL,
    "UpdatedAt"              timestamp    NULL,
    "UpdatedBy"              text         NULL
);
CREATE INDEX IF NOT EXISTS "IX_MaintenanceWindows_Active_Range"
    ON "MaintenanceWindows" ("IsActive", "StartAt", "EndAt");

-- =========================================================
-- Mobile site photo + per-device photo proof (2026-06-03)
-- =========================================================
ALTER TABLE "MobileAttendanceRecords" ADD COLUMN IF NOT EXISTS "SitePhotoUrl" VARCHAR(500);
ALTER TABLE "AuthorizedMobileDevices" ADD COLUMN IF NOT EXISTS "RequirePhotoProof" BOOLEAN NOT NULL DEFAULT false;

-- =========================================================
-- 20260605100000_AddMobileLocationEmployees (Phase 1)
-- =========================================================
ALTER TABLE "AuthorizedMobileDevices"
    ADD COLUMN IF NOT EXISTS "SelectedLocationIdsJson" character varying(4000);

ALTER TABLE "DeviceChangeRequests"
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

-- =========================================================
-- Mark ALL migrations as applied in __EFMigrationsHistory
-- =========================================================
INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
VALUES
    ('20260325000000_AddContractEndDateToEmployees', '8.0.0'),
    ('20260508104414_AddBranchPermissions', '8.0.0'),
    ('20260508152741_AddBranchIdToEmployee', '8.0.0'),
    ('20260525120000_RestoreWorkScheduleMultiShiftIndex', '8.0.0'),
    ('20260525140000_AddNewPunchTypeToAttendanceCorrection', '8.0.0'),
    ('20260526054332_AddScheduleApprovalRecords', '8.0.0'),
    ('20260526120000_AddCommunicationPublicShare', '8.0.0'),
    ('20260527120000_FixOrgAssignmentCareerHistoryIndex', '8.0.0'),
    ('20260527140000_EnhanceTaskAssignment', '8.0.0'),
    ('20260528120000_ShiftSwapFkToShiftTemplate', '8.0.0'),
    ('20260528180000_AddAttendanceUniqueDevicePinTime', '8.0.0'),
    ('20260603100000_AddRequirePhotoProofToAuthorizedDevice', '8.0.0'),
    ('20260605100000_AddMobileLocationEmployees', '8.0.0')
ON CONFLICT ("MigrationId") DO NOTHING;

-- =========================================================
-- FundTransfers (chuyển quỹ thu chi)
-- =========================================================
CREATE TABLE IF NOT EXISTS "FundTransfers" (
    "Id" uuid NOT NULL,
    "TransferCode" character varying(50) NOT NULL,
    "FromBankAccountId" uuid,
    "ToBankAccountId" uuid,
    "Amount" numeric(18,2) NOT NULL,
    "TransferDate" timestamp without time zone NOT NULL,
    "Description" character varying(500) NOT NULL,
    "InternalNote" character varying(1000),
    "StoreId" uuid,
    "CreatedByUserId" uuid NOT NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone,
    "CreatedBy" text,
    "UpdatedBy" text,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_FundTransfers" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_FundTransfers_BankAccounts_FromBankAccountId"
        FOREIGN KEY ("FromBankAccountId") REFERENCES "BankAccounts" ("Id") ON DELETE SET NULL,
    CONSTRAINT "FK_FundTransfers_BankAccounts_ToBankAccountId"
        FOREIGN KEY ("ToBankAccountId") REFERENCES "BankAccounts" ("Id") ON DELETE SET NULL,
    CONSTRAINT "FK_FundTransfers_AspNetUsers_CreatedByUserId"
        FOREIGN KEY ("CreatedByUserId") REFERENCES "AspNetUsers" ("Id") ON DELETE RESTRICT
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_FundTransfers_TransferCode"
    ON "FundTransfers" ("TransferCode");
CREATE INDEX IF NOT EXISTS "IX_FundTransfers_TransferDate"
    ON "FundTransfers" ("TransferDate");
CREATE INDEX IF NOT EXISTS "IX_FundTransfers_StoreId_TransferDate"
    ON "FundTransfers" ("StoreId", "TransferDate");

-- Feedbacks / FeedbackReplies (phiếu kiến nghị / phản ánh ý kiến)
CREATE TABLE IF NOT EXISTS "Feedbacks" (
    "Id" UUID NOT NULL PRIMARY KEY,
    "SenderEmployeeId" UUID,
    "IsAnonymous" BOOLEAN NOT NULL DEFAULT FALSE,
    "RecipientEmployeeId" UUID,
    "Title" VARCHAR(300) NOT NULL,
    "Content" VARCHAR(5000) NOT NULL,
    "ImageUrls" VARCHAR(2000),
    "Category" VARCHAR(50) NOT NULL DEFAULT 'General',
    "Status" VARCHAR(30) NOT NULL DEFAULT 'Pending',
    "Response" VARCHAR(5000),
    "RespondedByEmployeeId" UUID,
    "RespondedAt" TIMESTAMP WITHOUT TIME ZONE,
    "StoreId" UUID,
    "CreatedAt" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP WITHOUT TIME ZONE,
    "UpdatedBy" TEXT,
    "CreatedBy" TEXT,
    "IsActive" BOOLEAN NOT NULL DEFAULT TRUE,
    "LastModified" TIMESTAMP WITHOUT TIME ZONE,
    "LastModifiedBy" TEXT,
    "Deleted" TIMESTAMP WITHOUT TIME ZONE,
    "DeletedBy" TEXT
);
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "ImageUrls" VARCHAR(2000);
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "IsActive" BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "LastModified" TIMESTAMP WITHOUT TIME ZONE;
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "LastModifiedBy" TEXT;
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "Deleted" TIMESTAMP WITHOUT TIME ZONE;
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "DeletedBy" TEXT;
CREATE INDEX IF NOT EXISTS "IX_Feedbacks_StoreId_Status" ON "Feedbacks" ("StoreId", "Status");
CREATE INDEX IF NOT EXISTS "IX_Feedbacks_SenderEmployeeId" ON "Feedbacks" ("SenderEmployeeId");
CREATE INDEX IF NOT EXISTS "IX_Feedbacks_RecipientEmployeeId" ON "Feedbacks" ("RecipientEmployeeId");

CREATE TABLE IF NOT EXISTS "FeedbackReplies" (
    "Id" UUID NOT NULL PRIMARY KEY,
    "FeedbackId" UUID NOT NULL,
    "SenderEmployeeId" UUID,
    "Content" VARCHAR(5000) NOT NULL,
    "ImageUrls" VARCHAR(2000),
    "IsFromSender" BOOLEAN NOT NULL DEFAULT FALSE,
    "StoreId" UUID,
    "CreatedAt" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP WITHOUT TIME ZONE,
    "UpdatedBy" TEXT,
    "CreatedBy" TEXT
);
CREATE INDEX IF NOT EXISTS "IX_FeedbackReplies_FeedbackId" ON "FeedbackReplies" ("FeedbackId");
CREATE INDEX IF NOT EXISTS "IX_FeedbackReplies_SenderEmployeeId" ON "FeedbackReplies" ("SenderEmployeeId");
CREATE INDEX IF NOT EXISTS "IX_FeedbackReplies_StoreId" ON "FeedbackReplies" ("StoreId");

-- Cập nhật hotline / Zalo hỗ trợ kỹ thuật (landing + public settings)
UPDATE "AppSettings"
SET "Value" = '0973 024 042', "UpdatedAt" = NOW()
WHERE "Key" = 'technical_support_phone';

UPDATE "AppSettings"
SET "Value" = '0973024042', "UpdatedAt" = NOW()
WHERE "Key" = 'zalo_url';

-- =========================================================
-- PosPrintTemplates (mẫu in POS K58/K80/A5/A4)
-- =========================================================
CREATE TABLE IF NOT EXISTS "PosPrintTemplates" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL,
    "Name" varchar(120) NOT NULL,
    "DocumentType" integer NOT NULL DEFAULT 1,
    "PaperSize" integer NOT NULL DEFAULT 1,
    "HtmlContent" text NOT NULL DEFAULT '',
    "IsDefault" boolean NOT NULL DEFAULT false,
    "IsActive" boolean NOT NULL DEFAULT true,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "CreatedAt" timestamp with time zone NOT NULL DEFAULT NOW(),
    "CreatedBy" varchar(256) NULL,
    "UpdatedAt" timestamp with time zone NULL,
    "UpdatedBy" varchar(256) NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp with time zone NULL,
    "DeletedBy" varchar(256) NULL,
    CONSTRAINT "FK_PosPrintTemplates_Stores_StoreId"
        FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_PosPrintTemplates_StoreId_DocumentType_IsDefault"
    ON "PosPrintTemplates" ("StoreId", "DocumentType", "IsDefault");
CREATE INDEX IF NOT EXISTS "IX_PosPrintTemplates_StoreId_DocumentType_PaperSize_Name"
    ON "PosPrintTemplates" ("StoreId", "DocumentType", "PaperSize", "Name");

ALTER TABLE "PosPrintTemplates" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone;
ALTER TABLE "PosPrintTemplates" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text;

-- In đa máy: nhiều route cho cùng loại chứng từ
ALTER TABLE "PosPrinterDocumentRoutes"
    DROP CONSTRAINT IF EXISTS "PosPrinterDocumentRoutes_StoreId_DocumentType_key";
DROP INDEX IF EXISTS "IX_PosPrinterDocumentRoutes_StoreId_DocumentType";
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosPrinterDocumentRoutes_StoreId_DocumentType_PrinterId"
    ON "PosPrinterDocumentRoutes" ("StoreId", "DocumentType", "PrinterId");

-- Gán máy in theo sản phẩm / nhóm hàng POS
ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "DefaultPrinterId" uuid NULL
        REFERENCES "PosStorePrinters"("Id") ON DELETE SET NULL;

ALTER TABLE "PosProductCategories"
    ADD COLUMN IF NOT EXISTS "DefaultPrinterId" uuid NULL
        REFERENCES "PosStorePrinters"("Id") ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS "IX_PosProducts_StoreId_DefaultPrinterId"
    ON "PosProducts" ("StoreId", "DefaultPrinterId");

CREATE INDEX IF NOT EXISTS "IX_PosProductCategories_StoreId_DefaultPrinterId"
    ON "PosProductCategories" ("StoreId", "DefaultPrinterId");

ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "WarrantyMonths" integer NULL;

ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "RequiresSerial" boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS "PosProductWarrantyRegistrations" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "SaleOrderId" uuid NOT NULL REFERENCES "PosSaleOrders"("Id") ON DELETE CASCADE,
    "SaleOrderLineId" uuid NOT NULL REFERENCES "PosSaleOrderLines"("Id") ON DELETE CASCADE,
    "ProductId" uuid NOT NULL REFERENCES "PosProducts"("Id") ON DELETE RESTRICT,
    "VariantId" uuid NULL REFERENCES "PosProductVariants"("Id") ON DELETE SET NULL,
    "CustomerId" uuid NULL REFERENCES "PosCustomers"("Id") ON DELETE SET NULL,
    "SerialNumber" character varying(100) NOT NULL,
    "Imei" character varying(50) NULL,
    "WarrantyMonths" integer NOT NULL DEFAULT 0,
    "SaleDate" timestamp without time zone NOT NULL,
    "WarrantyExpiry" timestamp without time zone NOT NULL,
    "Status" integer NOT NULL DEFAULT 0,
    "Note" character varying(500) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosProductWarrantyRegistrations_StoreId_SerialNumber"
    ON "PosProductWarrantyRegistrations" ("StoreId", "SerialNumber")
    WHERE "Deleted" IS NULL AND "Status" = 0;

CREATE INDEX IF NOT EXISTS "IX_PosProductWarrantyRegistrations_StoreId_SaleOrderId"
    ON "PosProductWarrantyRegistrations" ("StoreId", "SaleOrderId");

CREATE INDEX IF NOT EXISTS "IX_PosProductWarrantyRegistrations_StoreId_ProductId"
    ON "PosProductWarrantyRegistrations" ("StoreId", "ProductId");

CREATE INDEX IF NOT EXISTS "IX_PosProductWarrantyRegistrations_StoreId_WarrantyExpiry"
    ON "PosProductWarrantyRegistrations" ("StoreId", "WarrantyExpiry")
    WHERE "Deleted" IS NULL AND "Status" = 0;

COMMIT;

-- Công nợ KH: thu nợ, tích điểm, voucher POS
BEGIN;

ALTER TABLE "PosCustomers"
    ADD COLUMN IF NOT EXISTS "PointBalance" numeric(18,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS "PosVouchers" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "Code" character varying(50) NOT NULL,
    "Name" character varying(200) NULL,
    "DiscountType" integer NOT NULL DEFAULT 1,
    "DiscountValue" numeric(18,2) NOT NULL DEFAULT 0,
    "MinOrderAmount" numeric(18,2) NOT NULL DEFAULT 0,
    "MaxDiscountAmount" numeric(18,2) NULL,
    "ValidFrom" timestamp without time zone NULL,
    "ValidTo" timestamp without time zone NULL,
    "MaxUses" integer NULL,
    "UsedCount" integer NOT NULL DEFAULT 0,
    "CustomerId" uuid NULL REFERENCES "PosCustomers"("Id") ON DELETE SET NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosVouchers_StoreId_Code"
    ON "PosVouchers" ("StoreId", "Code") WHERE "Deleted" IS NULL;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "VoucherId" uuid NULL;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "VoucherCode" character varying(50) NULL;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "VoucherDiscount" numeric(18,2) NOT NULL DEFAULT 0;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "PointsRedeemed" numeric(18,2) NOT NULL DEFAULT 0;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "PointsDiscount" numeric(18,2) NOT NULL DEFAULT 0;

ALTER TABLE "PosSaleOrders"
    ADD COLUMN IF NOT EXISTS "PointsEarned" numeric(18,2) NOT NULL DEFAULT 0;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosSaleOrders_VoucherId'
    ) THEN
        ALTER TABLE "PosSaleOrders"
            ADD CONSTRAINT "FK_PosSaleOrders_VoucherId"
            FOREIGN KEY ("VoucherId") REFERENCES "PosVouchers"("Id") ON DELETE SET NULL;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS "PosCustomerPayments" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "CustomerId" uuid NOT NULL REFERENCES "PosCustomers"("Id") ON DELETE CASCADE,
    "SaleOrderId" uuid NULL REFERENCES "PosSaleOrders"("Id") ON DELETE SET NULL,
    "PaymentNo" character varying(30) NOT NULL,
    "Amount" numeric(18,2) NOT NULL DEFAULT 0,
    "PaymentMethod" character varying(50) NOT NULL DEFAULT 'Tiền mặt',
    "PaidAt" timestamp without time zone NOT NULL,
    "Note" character varying(500) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

CREATE INDEX IF NOT EXISTS "IX_PosCustomerPayments_StoreId_CustomerId"
    ON "PosCustomerPayments" ("StoreId", "CustomerId");

CREATE TABLE IF NOT EXISTS "PosCustomerPointTransactions" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "CustomerId" uuid NOT NULL REFERENCES "PosCustomers"("Id") ON DELETE CASCADE,
    "SaleOrderId" uuid NULL REFERENCES "PosSaleOrders"("Id") ON DELETE SET NULL,
    "TransactionType" integer NOT NULL DEFAULT 0,
    "Points" numeric(18,2) NOT NULL DEFAULT 0,
    "BalanceAfter" numeric(18,2) NOT NULL DEFAULT 0,
    "Note" character varying(500) NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

CREATE INDEX IF NOT EXISTS "IX_PosCustomerPointTransactions_StoreId_CustomerId"
    ON "PosCustomerPointTransactions" ("StoreId", "CustomerId");

-- Quản lý lô / HSD POS (P0)
ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "TrackExpiry" boolean NOT NULL DEFAULT false;

ALTER TABLE "PosProducts"
    ADD COLUMN IF NOT EXISTS "ExpiryWarningDays" integer NOT NULL DEFAULT 30;

ALTER TABLE "PosStockReceiptLines"
    ADD COLUMN IF NOT EXISTS "LotNo" character varying(50) NULL;

ALTER TABLE "PosStockReceiptLines"
    ADD COLUMN IF NOT EXISTS "ManufactureDate" timestamp without time zone NULL;

ALTER TABLE "PosStockReceiptLines"
    ADD COLUMN IF NOT EXISTS "ExpiryDate" timestamp without time zone NULL;

ALTER TABLE "PosStockTransactions"
    ADD COLUMN IF NOT EXISTS "LotId" uuid NULL;

CREATE TABLE IF NOT EXISTS "PosStockLots" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "StoreId" uuid NOT NULL REFERENCES "Stores"("Id") ON DELETE CASCADE,
    "ProductId" uuid NOT NULL REFERENCES "PosProducts"("Id") ON DELETE RESTRICT,
    "VariantId" uuid NULL REFERENCES "PosProductVariants"("Id") ON DELETE SET NULL,
    "LotNo" character varying(50) NULL,
    "ManufactureDate" timestamp without time zone NULL,
    "ExpiryDate" timestamp without time zone NULL,
    "QtyOnHand" numeric(18,4) NOT NULL DEFAULT 0,
    "UnitCost" numeric(18,4) NOT NULL DEFAULT 0,
    "Status" integer NOT NULL DEFAULT 0,
    "StockReceiptId" uuid NULL REFERENCES "PosStockReceipts"("Id") ON DELETE SET NULL,
    "StockReceiptLineId" uuid NULL REFERENCES "PosStockReceiptLines"("Id") ON DELETE SET NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL
);

CREATE INDEX IF NOT EXISTS "IX_PosStockLots_StoreId_ProductId_Status"
    ON "PosStockLots" ("StoreId", "ProductId", "Status");

CREATE INDEX IF NOT EXISTS "IX_PosStockLots_StoreId_ExpiryDate"
    ON "PosStockLots" ("StoreId", "ExpiryDate")
    WHERE "Deleted" IS NULL AND "Status" = 0;

CREATE INDEX IF NOT EXISTS "IX_PosStockLots_StockReceiptLineId"
    ON "PosStockLots" ("StockReceiptLineId");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosStockTransactions_PosStockLots_LotId'
    ) THEN
        ALTER TABLE "PosStockTransactions"
            ADD CONSTRAINT "FK_PosStockTransactions_PosStockLots_LotId"
            FOREIGN KEY ("LotId") REFERENCES "PosStockLots"("Id") ON DELETE SET NULL;
    END IF;
END $$;

COMMIT;

SELECT 'Migration script completed successfully' AS status;
