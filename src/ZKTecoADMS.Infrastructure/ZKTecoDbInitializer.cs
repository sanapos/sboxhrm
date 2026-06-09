using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace ZKTecoADMS.Infrastructure;

public class ZKTecoDbInitializer(
    ZKTecoDbContext context,
    ILogger<ZKTecoDbInitializer> logger,
    UserManager<ApplicationUser> userManager,
    RoleManager<IdentityRole<Guid>> roleManager
)
{
    // Known GUIDs from init_data.sql for consistency
    private Guid ManagerUserId = Guid.Parse("698ba485-023f-4cf8-8439-99e7d04c459a");
    public async Task InitialiseAsync()
    {
        try
        {
            if (context.Database.IsNpgsql())
            {
                // Check if there are any pending migrations
                var pendingMigrations = await context.Database.GetPendingMigrationsAsync();
                
                if (pendingMigrations.Any())
                {
                    logger.LogInformation("Applying {Count} pending migrations...", pendingMigrations.Count());
                    try
                    {
                        await context.Database.MigrateAsync();
                        logger.LogInformation("Migrations applied successfully.");
                    }
                    catch (Exception migrationEx)
                    {
                        logger.LogWarning(migrationEx, "Skipping automatic migration because an existing migration failed. Continuing with targeted schema bootstrap.");
                    }
                }
                else
                {
                    logger.LogInformation("Database is up to date. No pending migrations.");
                }

                await context.Database.ExecuteSqlRawAsync(
                    "ALTER TABLE \"Employees\" ADD COLUMN IF NOT EXISTS \"DirectManagerEmployeeId\" uuid NULL;");

                await context.Database.ExecuteSqlRawAsync(
                    "ALTER TABLE \"Leaves\" ADD COLUMN IF NOT EXISTS \"EmployeeId\" uuid NULL;");

                await context.Database.ExecuteSqlRawAsync(
                    "ALTER TABLE \"Employees\" ADD COLUMN IF NOT EXISTS \"ContractEndDate\" timestamp without time zone NULL;");

                await context.Database.ExecuteSqlRawAsync(
                    "ALTER TABLE \"Departments\" ADD COLUMN IF NOT EXISTS \"Positions\" VARCHAR(2000);");

                // =============== Mobile Attendance Tables ===============
                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""MobileAttendanceSettings"" (
                        ""Id"" uuid NOT NULL DEFAULT gen_random_uuid(),
                        ""StoreId"" uuid NOT NULL,
                        ""EnableFaceId"" boolean NOT NULL DEFAULT true,
                        ""EnableGps"" boolean NOT NULL DEFAULT true,
                        ""EnableWifi"" boolean NOT NULL DEFAULT false,
                        ""EnableLivenessDetection"" boolean NOT NULL DEFAULT true,
                        ""VerificationMode"" VARCHAR(10) NOT NULL DEFAULT 'all',
                        ""GpsRadiusMeters"" integer NOT NULL DEFAULT 100,
                        ""MinFaceMatchScore"" double precision NOT NULL DEFAULT 80.0,
                        ""AutoApproveInRange"" boolean NOT NULL DEFAULT true,
                        ""AllowManualApproval"" boolean NOT NULL DEFAULT true,
                        ""MaxPhotosPerRegistration"" integer NOT NULL DEFAULT 5,
                        ""MaxPunchesPerDay"" integer NOT NULL DEFAULT 4,
                        ""RequirePhotoProof"" boolean NOT NULL DEFAULT false,
                        ""MinPunchIntervalMinutes"" integer NOT NULL DEFAULT 5,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""CreatedBy"" text,
                        ""UpdatedBy"" text,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""PK_MobileAttendanceSettings"" PRIMARY KEY (""Id""),
                        CONSTRAINT ""FK_MobileAttendanceSettings_Stores_StoreId"" FOREIGN KEY (""StoreId"") REFERENCES ""Stores"" (""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_MobileAttendanceSettings_StoreId"" ON ""MobileAttendanceSettings"" (""StoreId"");

                    CREATE TABLE IF NOT EXISTS ""MobileWorkLocations"" (
                        ""Id"" uuid NOT NULL DEFAULT gen_random_uuid(),
                        ""StoreId"" uuid NOT NULL,
                        ""Name"" character varying(200) NOT NULL,
                        ""Address"" character varying(500) NOT NULL DEFAULT '',
                        ""Latitude"" double precision NOT NULL DEFAULT 0,
                        ""Longitude"" double precision NOT NULL DEFAULT 0,
                        ""Radius"" integer NOT NULL DEFAULT 100,
                        ""AutoApproveInRange"" boolean NOT NULL DEFAULT true,
                        ""WifiSsid"" character varying(200),
                        ""WifiBssid"" character varying(200),
                        ""AllowedIpRange"" character varying(500),
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""CreatedBy"" text,
                        ""UpdatedBy"" text,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""PK_MobileWorkLocations"" PRIMARY KEY (""Id""),
                        CONSTRAINT ""FK_MobileWorkLocations_Stores_StoreId"" FOREIGN KEY (""StoreId"") REFERENCES ""Stores"" (""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_MobileWorkLocations_StoreId"" ON ""MobileWorkLocations"" (""StoreId"");

                    CREATE TABLE IF NOT EXISTS ""MobileFaceRegistrations"" (
                        ""Id"" uuid NOT NULL DEFAULT gen_random_uuid(),
                        ""StoreId"" uuid NOT NULL,
                        ""OdooEmployeeId"" character varying(100) NOT NULL,
                        ""EmployeeName"" character varying(200) NOT NULL,
                        ""EmployeeCode"" character varying(50),
                        ""Department"" character varying(200),
                        ""FaceImagesJson"" text NOT NULL DEFAULT '[]',
                        ""IsVerified"" boolean NOT NULL DEFAULT false,
                        ""RegisteredAt"" timestamp without time zone,
                        ""LastVerifiedAt"" timestamp without time zone,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""CreatedBy"" text,
                        ""UpdatedBy"" text,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""PK_MobileFaceRegistrations"" PRIMARY KEY (""Id""),
                        CONSTRAINT ""FK_MobileFaceRegistrations_Stores_StoreId"" FOREIGN KEY (""StoreId"") REFERENCES ""Stores"" (""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_MobileFaceRegistrations_StoreId"" ON ""MobileFaceRegistrations"" (""StoreId"");
                    CREATE INDEX IF NOT EXISTS ""IX_MobileFaceRegistrations_OdooEmployeeId"" ON ""MobileFaceRegistrations"" (""OdooEmployeeId"");

                    CREATE TABLE IF NOT EXISTS ""AuthorizedMobileDevices"" (
                        ""Id"" uuid NOT NULL DEFAULT gen_random_uuid(),
                        ""StoreId"" uuid NOT NULL,
                        ""DeviceId"" character varying(200) NOT NULL,
                        ""DeviceName"" character varying(200) NOT NULL,
                        ""DeviceModel"" character varying(200) NOT NULL,
                        ""OsVersion"" character varying(50),
                        ""EmployeeId"" character varying(100),
                        ""EmployeeName"" character varying(200),
                        ""IsAuthorized"" boolean NOT NULL DEFAULT true,
                        ""CanUseFaceId"" boolean NOT NULL DEFAULT true,
                        ""CanUseGps"" boolean NOT NULL DEFAULT true,
                        ""AllowOutsideCheckIn"" boolean NOT NULL DEFAULT false,
                        ""RequirePhotoProof"" boolean NOT NULL DEFAULT false,
                        ""WifiBssid"" character varying(50),
                        ""AuthorizedAt"" timestamp without time zone,
                        ""LastUsedAt"" timestamp without time zone,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""CreatedBy"" text,
                        ""UpdatedBy"" text,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""PK_AuthorizedMobileDevices"" PRIMARY KEY (""Id""),
                        CONSTRAINT ""FK_AuthorizedMobileDevices_Stores_StoreId"" FOREIGN KEY (""StoreId"") REFERENCES ""Stores"" (""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_AuthorizedMobileDevices_StoreId"" ON ""AuthorizedMobileDevices"" (""StoreId"");
                    CREATE INDEX IF NOT EXISTS ""IX_AuthorizedMobileDevices_DeviceId"" ON ""AuthorizedMobileDevices"" (""DeviceId"");

                    CREATE TABLE IF NOT EXISTS ""MobileAttendanceRecords"" (
                        ""Id"" uuid NOT NULL DEFAULT gen_random_uuid(),
                        ""StoreId"" uuid NOT NULL,
                        ""OdooEmployeeId"" character varying(100) NOT NULL,
                        ""EmployeeName"" character varying(200) NOT NULL,
                        ""PunchTime"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""PunchType"" integer NOT NULL DEFAULT 0,
                        ""Latitude"" double precision,
                        ""Longitude"" double precision,
                        ""LocationName"" character varying(200),
                        ""DistanceFromLocation"" double precision,
                        ""FaceImageUrl"" character varying(500),
                        ""FaceMatchScore"" double precision,
                        ""VerifyMethod"" character varying(20) NOT NULL DEFAULT 'face_gps',
                        ""Status"" character varying(20) NOT NULL DEFAULT 'pending',
                        ""ApprovedBy"" character varying(200),
                        ""ApprovedAt"" timestamp without time zone,
                        ""RejectReason"" character varying(500),
                        ""DeviceId"" character varying(200),
                        ""DeviceName"" character varying(200),
                        ""Note"" character varying(500),
                        ""WifiSsid"" character varying(200),
                        ""WifiBssid"" character varying(50),
                        ""WifiIpAddress"" character varying(100),
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""CreatedBy"" text,
                        ""UpdatedBy"" text,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""PK_MobileAttendanceRecords"" PRIMARY KEY (""Id""),
                        CONSTRAINT ""FK_MobileAttendanceRecords_Stores_StoreId"" FOREIGN KEY (""StoreId"") REFERENCES ""Stores"" (""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_MobileAttendanceRecords_StoreId"" ON ""MobileAttendanceRecords"" (""StoreId"");
                    CREATE INDEX IF NOT EXISTS ""IX_MobileAttendanceRecords_OdooEmployeeId"" ON ""MobileAttendanceRecords"" (""OdooEmployeeId"");
                    CREATE INDEX IF NOT EXISTS ""IX_MobileAttendanceRecords_PunchTime"" ON ""MobileAttendanceRecords"" (""PunchTime"");
                    CREATE INDEX IF NOT EXISTS ""IX_MobileAttendanceRecords_Status"" ON ""MobileAttendanceRecords"" (""Status"");
                ");

                await context.Database.ExecuteSqlRawAsync(@"
                    DO $$ BEGIN
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'MobileAttendanceRecords') THEN
                            ALTER TABLE ""MobileAttendanceRecords"" ADD COLUMN IF NOT EXISTS ""WifiBssid"" VARCHAR(50);
                            ALTER TABLE ""MobileAttendanceRecords"" ADD COLUMN IF NOT EXISTS ""SitePhotoUrl"" VARCHAR(500);
                        END IF;
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'MobileAttendanceSettings') THEN
                            ALTER TABLE ""MobileAttendanceSettings"" ADD COLUMN IF NOT EXISTS ""MinPunchIntervalMinutes"" INTEGER NOT NULL DEFAULT 5;
                            ALTER TABLE ""MobileAttendanceSettings"" ADD COLUMN IF NOT EXISTS ""EnableWifi"" BOOLEAN NOT NULL DEFAULT false;
                            ALTER TABLE ""MobileAttendanceSettings"" ADD COLUMN IF NOT EXISTS ""VerificationMode"" VARCHAR(10) NOT NULL DEFAULT 'all';
                        END IF;
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'AuthorizedMobileDevices') THEN
                            ALTER TABLE ""AuthorizedMobileDevices"" ADD COLUMN IF NOT EXISTS ""RequirePhotoProof"" BOOLEAN NOT NULL DEFAULT false;
                        END IF;
                    END $$;");

                // Add missing columns that are in entities but not in any migration
                await context.Database.ExecuteSqlRawAsync(@"
                    DO $$ BEGIN
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'Holidays') THEN
                            ALTER TABLE ""Holidays"" ADD COLUMN IF NOT EXISTS ""EmployeeIds"" TEXT;
                            ALTER TABLE ""Holidays"" ADD COLUMN IF NOT EXISTS ""SalaryRate"" DOUBLE PRECISION NOT NULL DEFAULT 3.0;
                        END IF;
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'ShiftTemplates') THEN
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""Description"" TEXT;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""Code"" TEXT;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""EarlyCheckInMinutes"" INTEGER NOT NULL DEFAULT 30;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""LateGraceMinutes"" INTEGER NOT NULL DEFAULT 5;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""EarlyLeaveGraceMinutes"" INTEGER NOT NULL DEFAULT 5;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""OvertimeMinutesThreshold"" INTEGER NOT NULL DEFAULT 30;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""ShiftType"" TEXT;
                        END IF;
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'AttendanceCorrectionRequests') THEN
                            ALTER TABLE ""AttendanceCorrectionRequests"" ADD COLUMN IF NOT EXISTS ""EmployeeCode"" VARCHAR(100);
                        END IF;
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'SalaryProfiles') THEN
                            ALTER TABLE ""SalaryProfiles"" ADD COLUMN IF NOT EXISTS ""SocialInsuranceType"" INTEGER;
                        END IF;
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'AttendanceLogs') THEN
                            ALTER TABLE ""AttendanceLogs"" ADD COLUMN IF NOT EXISTS ""MobileAttendanceRecordId"" UUID;
                        END IF;
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'Devices') THEN
                            ALTER TABLE ""Devices"" ADD COLUMN IF NOT EXISTS ""DeviceType"" INTEGER NOT NULL DEFAULT 0;
                        END IF;
                    END $$;
                ");

                // ===== Bootstrap for migrations from AddBranchPermissions onwards =====
                await context.Database.ExecuteSqlRawAsync(@"
                    DO $$ BEGIN
                        -- PlainTextPassword was removed by AddBranchPermissions migration
                        ALTER TABLE ""AspNetUsers"" DROP COLUMN IF EXISTS ""PlainTextPassword"";

                        -- TaskComments new columns
                        ALTER TABLE ""TaskComments"" ADD COLUMN IF NOT EXISTS ""CommentType"" integer NOT NULL DEFAULT 0;
                        ALTER TABLE ""TaskComments"" ADD COLUMN IF NOT EXISTS ""ImageUrls"" character varying(4000);
                        ALTER TABLE ""TaskComments"" ADD COLUMN IF NOT EXISTS ""LinkUrls"" character varying(4000);
                        ALTER TABLE ""TaskComments"" ADD COLUMN IF NOT EXISTS ""ProgressSnapshot"" integer;

                        -- Payslips insurance/tax columns
                        ALTER TABLE ""Payslips"" ADD COLUMN IF NOT EXISTS ""Allowances"" numeric;
                        ALTER TABLE ""Payslips"" ADD COLUMN IF NOT EXISTS ""HealthInsurance"" numeric;
                        ALTER TABLE ""Payslips"" ADD COLUMN IF NOT EXISTS ""SocialInsurance"" numeric;
                        ALTER TABLE ""Payslips"" ADD COLUMN IF NOT EXISTS ""Tax"" numeric;
                        ALTER TABLE ""Payslips"" ADD COLUMN IF NOT EXISTS ""UnemploymentInsurance"" numeric;

                        -- Leaves approval columns
                        ALTER TABLE ""Leaves"" ADD COLUMN IF NOT EXISTS ""CurrentApprovalStep"" integer NOT NULL DEFAULT 0;
                        ALTER TABLE ""Leaves"" ADD COLUMN IF NOT EXISTS ""TotalApprovalLevels"" integer NOT NULL DEFAULT 0;
                        ALTER TABLE ""Leaves"" ADD COLUMN IF NOT EXISTS ""CountAsWork"" boolean NOT NULL DEFAULT FALSE;
                        ALTER TABLE ""Leaves"" ADD COLUMN IF NOT EXISTS ""PaymentSource"" integer NOT NULL DEFAULT 0;
                        ALTER TABLE ""Leaves"" ADD COLUMN IF NOT EXISTS ""SickLeaveMode"" integer NOT NULL DEFAULT 0;
                        ALTER TABLE ""Leaves"" ADD COLUMN IF NOT EXISTS ""BhxhDocumentNote"" text NULL;
                        ALTER TABLE ""Leaves"" ADD COLUMN IF NOT EXISTS ""AnnualLeaveDaysDeducted"" numeric NOT NULL DEFAULT 0;
                        ALTER TABLE ""Leaves"" ADD COLUMN IF NOT EXISTS ""AnnualBalanceApplied"" boolean NOT NULL DEFAULT FALSE;

                        -- AttendanceCorrectionRequests approval columns
                        ALTER TABLE ""AttendanceCorrectionRequests"" ADD COLUMN IF NOT EXISTS ""CurrentApprovalStep"" integer NOT NULL DEFAULT 0;
                        ALTER TABLE ""AttendanceCorrectionRequests"" ADD COLUMN IF NOT EXISTS ""TotalApprovalLevels"" integer NOT NULL DEFAULT 0;

                        -- Assets new columns
                        ALTER TABLE ""Assets"" ADD COLUMN IF NOT EXISTS ""Color"" text;
                        ALTER TABLE ""Assets"" ADD COLUMN IF NOT EXISTS ""QrCode"" text;
                        ALTER TABLE ""Assets"" ADD COLUMN IF NOT EXISTS ""Size"" text;

                        -- AssetInventoryItems
                        ALTER TABLE ""AssetInventoryItems"" ADD COLUMN IF NOT EXISTS ""StoredExpectedQuantity"" integer NOT NULL DEFAULT 0;

                        -- AdvanceRequests approval columns
                        ALTER TABLE ""AdvanceRequests"" ADD COLUMN IF NOT EXISTS ""CurrentApprovalStep"" integer NOT NULL DEFAULT 0;
                        ALTER TABLE ""AdvanceRequests"" ADD COLUMN IF NOT EXISTS ""TotalApprovalLevels"" integer NOT NULL DEFAULT 0;

                        -- Employees.BranchId
                        ALTER TABLE ""Employees"" ADD COLUMN IF NOT EXISTS ""BranchId"" uuid;

                        -- InternalCommunications public share
                        ALTER TABLE ""InternalCommunications"" ADD COLUMN IF NOT EXISTS ""IsPublicShareEnabled"" boolean NOT NULL DEFAULT false;
                        ALTER TABLE ""InternalCommunications"" ADD COLUMN IF NOT EXISTS ""PublicShareToken"" character varying(64);

                        -- ScheduleRegistrations approval columns
                        ALTER TABLE ""ScheduleRegistrations"" ADD COLUMN IF NOT EXISTS ""CurrentApprovalStep"" integer NOT NULL DEFAULT 0;
                        ALTER TABLE ""ScheduleRegistrations"" ADD COLUMN IF NOT EXISTS ""TotalApprovalLevels"" integer NOT NULL DEFAULT 1;

                        -- WorkTasks assignment enhancement
                        ALTER TABLE ""WorkTasks"" ADD COLUMN IF NOT EXISTS ""BranchId"" uuid;
                        ALTER TABLE ""WorkTasks"" ADD COLUMN IF NOT EXISTS ""DepartmentId"" uuid;
                        ALTER TABLE ""WorkTasks"" ADD COLUMN IF NOT EXISTS ""TemplateId"" uuid;
                        ALTER TABLE ""WorkTasks"" ADD COLUMN IF NOT EXISTS ""SlaReminderHours"" integer;
                        ALTER TABLE ""WorkTasks"" ADD COLUMN IF NOT EXISTS ""AcceptedAt"" timestamp without time zone;
                        ALTER TABLE ""WorkTasks"" ADD COLUMN IF NOT EXISTS ""RejectionReason"" character varying(500);
                        ALTER TABLE ""WorkTasks"" ADD COLUMN IF NOT EXISTS ""AssignmentNote"" character varying(1000);

                        -- AttendanceCorrectionRequests.NewPunchType
                        ALTER TABLE ""AttendanceCorrectionRequests"" ADD COLUMN IF NOT EXISTS ""NewPunchType"" character varying(20);
                    END $$;
                ");

                // Create tables from migrations if not existing
                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""AdvanceApprovalRecords"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""AdvanceRequestId"" uuid NOT NULL,
                        ""StepOrder"" integer NOT NULL,
                        ""StepName"" character varying(200),
                        ""AssignedUserId"" uuid,
                        ""AssignedUserName"" character varying(200),
                        ""ActualUserId"" uuid,
                        ""ActualUserName"" character varying(200),
                        ""Status"" integer NOT NULL DEFAULT 0,
                        ""Note"" character varying(1000),
                        ""ActionDate"" timestamp without time zone,
                        ""StoreId"" uuid,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        CONSTRAINT ""FK_AdvanceApprovalRecords_AdvanceRequests""
                            FOREIGN KEY (""AdvanceRequestId"") REFERENCES ""AdvanceRequests""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_AdvanceApprovalRecords_AdvanceRequestId"" ON ""AdvanceApprovalRecords""(""AdvanceRequestId"");
                    CREATE INDEX IF NOT EXISTS ""IX_AdvanceApprovalRecords_AssignedUserId"" ON ""AdvanceApprovalRecords""(""AssignedUserId"");

                    CREATE TABLE IF NOT EXISTS ""AppBugReports"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""UserId"" character varying(100),
                        ""UserName"" character varying(200),
                        ""UserEmail"" character varying(100),
                        ""StoreName"" character varying(200),
                        ""Type"" character varying(30) NOT NULL DEFAULT 'Bug',
                        ""Title"" character varying(300) NOT NULL DEFAULT '',
                        ""Content"" character varying(5000) NOT NULL DEFAULT '',
                        ""AppVersion"" character varying(50),
                        ""DeviceInfo"" character varying(200),
                        ""Status"" character varying(30) NOT NULL DEFAULT 'Open',
                        ""AdminNote"" character varying(2000),
                        ""ResolvedAt"" timestamp without time zone,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text
                    );

                    CREATE TABLE IF NOT EXISTS ""AppPages"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""Type"" character varying(30) NOT NULL DEFAULT '',
                        ""Title"" character varying(200) NOT NULL DEFAULT '',
                        ""Content"" character varying(100000),
                        ""IsPublished"" boolean NOT NULL DEFAULT false,
                        ""UpdatedByName"" character varying(200),
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_AppPages_Type"" ON ""AppPages""(""Type"");

                    CREATE TABLE IF NOT EXISTS ""ApprovalRecords"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""CorrectionRequestId"" uuid NOT NULL,
                        ""StepOrder"" integer NOT NULL,
                        ""StepName"" character varying(200),
                        ""AssignedUserId"" uuid,
                        ""AssignedUserName"" character varying(200),
                        ""ActualUserId"" uuid,
                        ""ActualUserName"" character varying(200),
                        ""Status"" integer NOT NULL DEFAULT 0,
                        ""Note"" character varying(1000),
                        ""ActionDate"" timestamp without time zone,
                        ""StoreId"" uuid,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        CONSTRAINT ""FK_ApprovalRecords_AttendanceCorrectionRequests""
                            FOREIGN KEY (""CorrectionRequestId"") REFERENCES ""AttendanceCorrectionRequests""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_ApprovalRecords_CorrectionRequestId"" ON ""ApprovalRecords""(""CorrectionRequestId"");

                    CREATE TABLE IF NOT EXISTS ""BranchPermissions"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""UserId"" uuid NOT NULL,
                        ""BranchId"" uuid,
                        ""IncludeChildren"" boolean NOT NULL DEFAULT false,
                        ""StoreId"" uuid,
                        ""CanView"" boolean NOT NULL DEFAULT false,
                        ""CanCreate"" boolean NOT NULL DEFAULT false,
                        ""CanEdit"" boolean NOT NULL DEFAULT false,
                        ""CanDelete"" boolean NOT NULL DEFAULT false,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""GrantedBy"" character varying(100),
                        ""Note"" character varying(500),
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        CONSTRAINT ""FK_BranchPermissions_AspNetUsers_UserId""
                            FOREIGN KEY (""UserId"") REFERENCES ""AspNetUsers""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_BranchPermissions_UserId"" ON ""BranchPermissions""(""UserId"");
                    CREATE INDEX IF NOT EXISTS ""IX_BranchPermissions_StoreId"" ON ""BranchPermissions""(""StoreId"");

                    CREATE TABLE IF NOT EXISTS ""DeviceChangeRequests"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""EmployeeId"" character varying(100) NOT NULL DEFAULT '',
                        ""EmployeeName"" character varying(200) NOT NULL DEFAULT '',
                        ""OldDeviceRecordId"" uuid NOT NULL DEFAULT gen_random_uuid(),
                        ""OldDeviceName"" character varying(200) NOT NULL DEFAULT '',
                        ""OldDeviceModel"" character varying(200) NOT NULL DEFAULT '',
                        ""NewDeviceId"" character varying(200) NOT NULL DEFAULT '',
                        ""NewDeviceName"" character varying(200) NOT NULL DEFAULT '',
                        ""NewDeviceModel"" character varying(200) NOT NULL DEFAULT '',
                        ""NewOsVersion"" character varying(50),
                        ""NewWifiBssid"" character varying(50),
                        ""NewFaceImagesJson"" text NOT NULL DEFAULT '[]',
                        ""Status"" integer NOT NULL DEFAULT 0,
                        ""Reason"" character varying(500),
                        ""RequestedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""ApprovedBy"" uuid,
                        ""ApprovedAt"" timestamp without time zone,
                        ""RejectReason"" character varying(500),
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_DeviceChangeRequests_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE
                    );

                    CREATE TABLE IF NOT EXISTS ""EmployeeLiveLocations"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""EmployeeId"" character varying(100) NOT NULL DEFAULT '',
                        ""Latitude"" double precision NOT NULL DEFAULT 0,
                        ""Longitude"" double precision NOT NULL DEFAULT 0,
                        ""Accuracy"" double precision,
                        ""UpdatedAt"" timestamp without time zone NOT NULL DEFAULT NOW()
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_EmployeeLiveLocations_StoreId_EmployeeId"" ON ""EmployeeLiveLocations""(""StoreId"", ""EmployeeId"");

                    CREATE TABLE IF NOT EXISTS ""FieldLocations"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""Name"" character varying(300) NOT NULL DEFAULT '',
                        ""Address"" character varying(500),
                        ""ContactName"" character varying(200),
                        ""ContactPhone"" character varying(50),
                        ""ContactEmail"" character varying(200),
                        ""Note"" character varying(1000),
                        ""Latitude"" double precision NOT NULL DEFAULT 0,
                        ""Longitude"" double precision NOT NULL DEFAULT 0,
                        ""Radius"" integer NOT NULL DEFAULT 100,
                        ""PhotoUrlsJson"" text,
                        ""RegisteredByEmployeeId"" character varying(100),
                        ""RegisteredByEmployeeName"" character varying(200),
                        ""Category"" character varying(50),
                        ""IsApproved"" boolean NOT NULL DEFAULT false,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_FieldLocations_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_FieldLocations_StoreId"" ON ""FieldLocations""(""StoreId"");

                    CREATE TABLE IF NOT EXISTS ""ScheduleApprovalRecords"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""ScheduleRegistrationId"" uuid NOT NULL,
                        ""StepOrder"" integer NOT NULL,
                        ""StepName"" character varying(200),
                        ""AssignedUserId"" uuid,
                        ""AssignedUserName"" character varying(200),
                        ""ActualUserId"" uuid,
                        ""ActualUserName"" character varying(200),
                        ""Status"" integer NOT NULL DEFAULT 0,
                        ""Note"" character varying(1000),
                        ""ActionDate"" timestamp without time zone,
                        ""StoreId"" uuid,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        CONSTRAINT ""FK_ScheduleApprovalRecords_ScheduleRegistrations""
                            FOREIGN KEY (""ScheduleRegistrationId"") REFERENCES ""ScheduleRegistrations""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_ScheduleApprovalRecords_ScheduleRegistrationId"" ON ""ScheduleApprovalRecords""(""ScheduleRegistrationId"");

                    CREATE TABLE IF NOT EXISTS ""TaskTemplates"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""Name"" character varying(120) NOT NULL DEFAULT '',
                        ""Title"" character varying(200) NOT NULL DEFAULT '',
                        ""Description"" character varying(2000),
                        ""TaskType"" integer NOT NULL DEFAULT 0,
                        ""Priority"" integer NOT NULL DEFAULT 0,
                        ""EstimatedHours"" numeric,
                        ""DefaultSlaReminderHours"" integer,
                        ""Tags"" character varying(500),
                        ""Checklist"" character varying(4000),
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""CreatedBy"" text,
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_TaskTemplates_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_TaskTemplates_StoreId"" ON ""TaskTemplates""(""StoreId"");

                    CREATE TABLE IF NOT EXISTS ""TaskDependencies"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""TaskId"" uuid NOT NULL,
                        ""DependsOnTaskId"" uuid NOT NULL,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        CONSTRAINT ""FK_TaskDependencies_WorkTasks_TaskId""
                            FOREIGN KEY (""TaskId"") REFERENCES ""WorkTasks""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_TaskDependencies_WorkTasks_DependsOnTaskId""
                            FOREIGN KEY (""DependsOnTaskId"") REFERENCES ""WorkTasks""(""Id"") ON DELETE RESTRICT
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_TaskDependencies_TaskId_DependsOnTaskId"" ON ""TaskDependencies""(""TaskId"", ""DependsOnTaskId"");
                ");

                // WorkSchedules: ensure per-shift unique index
                await context.Database.ExecuteSqlRawAsync(@"
                    DROP INDEX IF EXISTS ""IX_WorkSchedules_Employee_Date"";
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_WorkSchedules_Employee_Date_Shift""
                        ON ""WorkSchedules"" (""EmployeeId"", ""Date"", ""ShiftId"");
                ");

                // OrgAssignments: fix index to allow multiple assignments per person as long as one is active
                await context.Database.ExecuteSqlRawAsync(@"
                    DO $$ BEGIN
                        DROP INDEX IF EXISTS ""IX_OrgAssignments_Emp_Dept_Pos"";
                        IF NOT EXISTS (
                            SELECT 1 FROM pg_indexes WHERE indexname = 'IX_OrgAssignments_Emp_Dept_Pos_Active'
                        ) THEN
                            CREATE UNIQUE INDEX ""IX_OrgAssignments_Emp_Dept_Pos_Active""
                                ON ""OrgAssignments"" (""EmployeeId"", ""DepartmentId"", ""PositionId"")
                                WHERE ""Deleted"" IS NULL AND ""EndDate"" IS NULL;
                        END IF;
                    END $$;
                ");

                // AttendanceLogs: unique index on (DeviceId, PIN, AttendanceTime)
                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE UNIQUE INDEX IF NOT EXISTS ""UX_Attendance_Device_Pin_Time""
                        ON ""AttendanceLogs"" (""DeviceId"", ""PIN"", ""AttendanceTime"");
                ");

                // FK → AttendanceLogs: ON DELETE SET NULL (xóa chấm công / phiếu duyệt xóa)
                try
                {
                    await context.Database.ExecuteSqlRawAsync(@"
                        DO $$
                        DECLARE r RECORD;
                        DECLARE att_oid oid;
                        BEGIN
                            SELECT c.oid INTO att_oid
                            FROM pg_class c
                            JOIN pg_namespace n ON n.oid = c.relnamespace
                            WHERE n.nspname = 'public' AND c.relname = 'AttendanceLogs';
                            IF att_oid IS NULL THEN
                                RETURN;
                            END IF;

                            FOR r IN
                                SELECT c.conname, t.relname AS tbl
                                FROM pg_constraint c
                                JOIN pg_class t ON c.conrelid = t.oid
                                WHERE c.contype = 'f'
                                  AND c.confrelid = att_oid
                                  AND t.relname IN (
                                      'AttendanceCorrectionRequests','PenaltyTickets',
                                      'MealRecords','Shifts')
                            LOOP
                                EXECUTE format(
                                    'ALTER TABLE %I DROP CONSTRAINT %I',
                                    r.tbl, r.conname);
                            END LOOP;

                            IF NOT EXISTS (
                                SELECT 1 FROM pg_constraint
                                WHERE conname = 'FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId')
                            THEN
                                ALTER TABLE ""AttendanceCorrectionRequests""
                                    ADD CONSTRAINT ""FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId""
                                    FOREIGN KEY (""AttendanceId"") REFERENCES ""AttendanceLogs""(""Id"")
                                    ON DELETE SET NULL;
                            END IF;

                            IF NOT EXISTS (
                                SELECT 1 FROM pg_constraint
                                WHERE conname = 'FK_PenaltyTickets_AttendanceLogs_AttendanceId')
                            THEN
                                ALTER TABLE ""PenaltyTickets""
                                    ADD CONSTRAINT ""FK_PenaltyTickets_AttendanceLogs_AttendanceId""
                                    FOREIGN KEY (""AttendanceId"") REFERENCES ""AttendanceLogs""(""Id"")
                                    ON DELETE SET NULL;
                            END IF;

                            IF NOT EXISTS (
                                SELECT 1 FROM pg_constraint
                                WHERE conname = 'FK_MealRecords_AttendanceLogs_AttendanceId')
                            THEN
                                ALTER TABLE ""MealRecords""
                                    ADD CONSTRAINT ""FK_MealRecords_AttendanceLogs_AttendanceId""
                                    FOREIGN KEY (""AttendanceId"") REFERENCES ""AttendanceLogs""(""Id"")
                                    ON DELETE SET NULL;
                            END IF;

                            IF NOT EXISTS (
                                SELECT 1 FROM pg_constraint WHERE conname = 'FK_Shifts_AttendanceLogs_CheckIn')
                            THEN
                                ALTER TABLE ""Shifts""
                                    ADD CONSTRAINT ""FK_Shifts_AttendanceLogs_CheckIn""
                                    FOREIGN KEY (""CheckInAttendanceId"") REFERENCES ""AttendanceLogs""(""Id"")
                                    ON DELETE SET NULL;
                            END IF;

                            IF NOT EXISTS (
                                SELECT 1 FROM pg_constraint WHERE conname = 'FK_Shifts_AttendanceLogs_CheckOut')
                            THEN
                                ALTER TABLE ""Shifts""
                                    ADD CONSTRAINT ""FK_Shifts_AttendanceLogs_CheckOut""
                                    FOREIGN KEY (""CheckOutAttendanceId"") REFERENCES ""AttendanceLogs""(""Id"")
                                    ON DELETE SET NULL;
                            END IF;
                        END $$;
                    ");
                }
                catch (Exception fkEx)
                {
                    logger.LogWarning(fkEx,
                        "AttendanceLogs FK repair skipped (non-fatal). Delete-unlink still uses AttendanceDeletePreparer SQL.");
                }

                // InternalCommunications: public share token index
                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_InternalCommunications_PublicShareToken""
                        ON ""InternalCommunications"" (""PublicShareToken"")
                        WHERE ""PublicShareToken"" IS NOT NULL;
                ");

                // MaintenanceWindows table
                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""MaintenanceWindows"" (
                        ""Id""                     uuid         NOT NULL PRIMARY KEY,
                        ""Title""                  varchar(200) NOT NULL DEFAULT '',
                        ""Message""                text         NOT NULL DEFAULT '',
                        ""StartAt""                timestamp    NOT NULL DEFAULT NOW(),
                        ""EndAt""                  timestamp    NOT NULL DEFAULT NOW(),
                        ""AffectedModulesJson""    jsonb        NULL,
                        ""IsActive""               boolean      NOT NULL DEFAULT false,
                        ""BlockAccess""            boolean      NOT NULL DEFAULT true,
                        ""NotifyBeforeMinutesCsv"" varchar(100) NULL,
                        ""NotifiedMinutesCsv""     varchar(100) NULL,
                        ""StartNotified""          boolean      NOT NULL DEFAULT false,
                        ""EndNotified""            boolean      NOT NULL DEFAULT false,
                        ""CreatedByUserId""        uuid         NOT NULL DEFAULT gen_random_uuid(),
                        ""CreatedAt""              timestamp    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
                        ""CreatedBy""              text         NULL,
                        ""UpdatedAt""              timestamp    NULL,
                        ""UpdatedBy""              text         NULL
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_MaintenanceWindows_Active_Range""
                        ON ""MaintenanceWindows"" (""IsActive"", ""StartAt"", ""EndAt"");
                ");

                // Fix EmployeeTaxDeductions column names (lowercase → PascalCase)
                await context.Database.ExecuteSqlRawAsync(@"
                    DO $$
                    BEGIN
                        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'EmployeeTaxDeductions' AND column_name = 'id') THEN
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""id"" TO ""Id"";
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""employeeid"" TO ""EmployeeId"";
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""numberofdependents"" TO ""NumberOfDependents"";
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""mandatoryinsurance"" TO ""MandatoryInsurance"";
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""otherexemptions"" TO ""OtherExemptions"";
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""storeid"" TO ""StoreId"";
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""createdat"" TO ""CreatedAt"";
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""updatedat"" TO ""UpdatedAt"";
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""updatedby"" TO ""UpdatedBy"";
                            ALTER TABLE ""EmployeeTaxDeductions"" RENAME COLUMN ""createdby"" TO ""CreatedBy"";
                        END IF;
                    END $$;");

                // Notification Categories & Preferences tables
                // Feedbacks table
                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""Feedbacks"" (
                        ""Id"" UUID NOT NULL PRIMARY KEY,
                        ""SenderEmployeeId"" UUID,
                        ""IsAnonymous"" BOOLEAN NOT NULL DEFAULT FALSE,
                        ""RecipientEmployeeId"" UUID,
                        ""Title"" VARCHAR(300) NOT NULL,
                        ""Content"" VARCHAR(5000) NOT NULL,
                        ""Category"" VARCHAR(50) NOT NULL DEFAULT 'General',
                        ""Status"" VARCHAR(30) NOT NULL DEFAULT 'Pending',
                        ""Response"" VARCHAR(5000),
                        ""RespondedByEmployeeId"" UUID,
                        ""RespondedAt"" TIMESTAMP WITHOUT TIME ZONE,
                        ""StoreId"" UUID,
                        ""CreatedAt"" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" TIMESTAMP WITHOUT TIME ZONE,
                        ""UpdatedBy"" TEXT,
                        ""CreatedBy"" TEXT
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_Feedbacks_StoreId_Status"" ON ""Feedbacks"" (""StoreId"", ""Status"");
                    CREATE INDEX IF NOT EXISTS ""IX_Feedbacks_SenderEmployeeId"" ON ""Feedbacks"" (""SenderEmployeeId"");
                    CREATE INDEX IF NOT EXISTS ""IX_Feedbacks_RecipientEmployeeId"" ON ""Feedbacks"" (""RecipientEmployeeId"");
                    ALTER TABLE ""Feedbacks"" ADD COLUMN IF NOT EXISTS ""ImageUrls"" VARCHAR(2000);
                    ALTER TABLE ""Feedbacks"" ADD COLUMN IF NOT EXISTS ""IsActive"" BOOLEAN NOT NULL DEFAULT TRUE;
                    ALTER TABLE ""Feedbacks"" ADD COLUMN IF NOT EXISTS ""LastModified"" TIMESTAMP WITHOUT TIME ZONE;
                    ALTER TABLE ""Feedbacks"" ADD COLUMN IF NOT EXISTS ""LastModifiedBy"" TEXT;
                    ALTER TABLE ""Feedbacks"" ADD COLUMN IF NOT EXISTS ""Deleted"" TIMESTAMP WITHOUT TIME ZONE;
                    ALTER TABLE ""Feedbacks"" ADD COLUMN IF NOT EXISTS ""DeletedBy"" TEXT;
                ");

                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""FeedbackReplies"" (
                        ""Id"" UUID NOT NULL PRIMARY KEY,
                        ""FeedbackId"" UUID NOT NULL,
                        ""SenderEmployeeId"" UUID,
                        ""Content"" VARCHAR(5000) NOT NULL,
                        ""ImageUrls"" VARCHAR(2000),
                        ""IsFromSender"" BOOLEAN NOT NULL DEFAULT FALSE,
                        ""StoreId"" UUID,
                        ""CreatedAt"" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" TIMESTAMP WITHOUT TIME ZONE,
                        ""UpdatedBy"" TEXT,
                        ""CreatedBy"" TEXT
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_FeedbackReplies_FeedbackId"" ON ""FeedbackReplies"" (""FeedbackId"");
                    CREATE INDEX IF NOT EXISTS ""IX_FeedbackReplies_SenderEmployeeId"" ON ""FeedbackReplies"" (""SenderEmployeeId"");
                    CREATE INDEX IF NOT EXISTS ""IX_FeedbackReplies_StoreId"" ON ""FeedbackReplies"" (""StoreId"");
                ");

                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""ConsultationRequests"" (
                        ""Id"" UUID NOT NULL PRIMARY KEY,
                        ""Name"" VARCHAR(150) NOT NULL,
                        ""Phone"" VARCHAR(30) NOT NULL,
                        ""NormalizedPhone"" VARCHAR(30) NOT NULL DEFAULT '',
                        ""Company"" VARCHAR(200),
                        ""Province"" VARCHAR(120),
                        ""InterestedPlan"" VARCHAR(100),
                        ""Status"" VARCHAR(30) NOT NULL DEFAULT 'New',
                        ""Source"" VARCHAR(50) NOT NULL DEFAULT 'LandingPage',
                        ""Notes"" VARCHAR(1000),
                        ""AdminNote"" VARCHAR(1000),
                        ""ClientIp"" VARCHAR(100),
                        ""UserAgent"" VARCHAR(500),
                        ""StoreId"" UUID,
                        ""IsActive"" BOOLEAN NOT NULL DEFAULT TRUE,
                        ""LastModified"" TIMESTAMP WITHOUT TIME ZONE,
                        ""LastModifiedBy"" TEXT,
                        ""Deleted"" TIMESTAMP WITHOUT TIME ZONE,
                        ""DeletedBy"" TEXT,
                        ""CreatedAt"" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" TIMESTAMP WITHOUT TIME ZONE,
                        ""UpdatedBy"" TEXT,
                        ""CreatedBy"" TEXT
                    );
                    ALTER TABLE ""ConsultationRequests"" ADD COLUMN IF NOT EXISTS ""NormalizedPhone"" VARCHAR(30) NOT NULL DEFAULT '';
                    ALTER TABLE ""ConsultationRequests"" ADD COLUMN IF NOT EXISTS ""Province"" VARCHAR(120);
                    ALTER TABLE ""ConsultationRequests"" ADD COLUMN IF NOT EXISTS ""AdminNote"" VARCHAR(1000);
                    ALTER TABLE ""ConsultationRequests"" ADD COLUMN IF NOT EXISTS ""ClientIp"" VARCHAR(100);
                    ALTER TABLE ""ConsultationRequests"" ADD COLUMN IF NOT EXISTS ""UserAgent"" VARCHAR(500);
                    CREATE INDEX IF NOT EXISTS ""IX_ConsultationRequests_CreatedAt"" ON ""ConsultationRequests"" (""CreatedAt"");
                    CREATE INDEX IF NOT EXISTS ""IX_ConsultationRequests_Status"" ON ""ConsultationRequests"" (""Status"");
                    CREATE INDEX IF NOT EXISTS ""IX_ConsultationRequests_Phone"" ON ""ConsultationRequests"" (""Phone"");
                    CREATE INDEX IF NOT EXISTS ""IX_ConsultationRequests_NormalizedPhone"" ON ""ConsultationRequests"" (""NormalizedPhone"");
                ");

                await context.Database.ExecuteSqlRawAsync(@"
                    DO $$ BEGIN
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'Notifications') THEN
                            ALTER TABLE ""Notifications"" ADD COLUMN IF NOT EXISTS ""CategoryCode"" VARCHAR(50);
                            CREATE INDEX IF NOT EXISTS ""IX_Notifications_CategoryCode"" ON ""Notifications"" (""CategoryCode"");
                        END IF;
                    END $$;
                ");

                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""NotificationCategories"" (
                        ""Id"" UUID NOT NULL PRIMARY KEY,
                        ""Code"" VARCHAR(50) NOT NULL,
                        ""DisplayName"" VARCHAR(100) NOT NULL,
                        ""Description"" VARCHAR(255),
                        ""Icon"" VARCHAR(50),
                        ""DisplayOrder"" INTEGER NOT NULL DEFAULT 0,
                        ""IsSystem"" BOOLEAN NOT NULL DEFAULT TRUE,
                        ""DefaultEnabled"" BOOLEAN NOT NULL DEFAULT TRUE,
                        ""StoreId"" UUID,
                        ""CreatedAt"" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" TIMESTAMP WITHOUT TIME ZONE,
                        ""UpdatedBy"" TEXT,
                        ""CreatedBy"" TEXT
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_NotificationCategories_Code"" ON ""NotificationCategories"" (""Code"");
                    CREATE INDEX IF NOT EXISTS ""IX_NotificationCategories_StoreId"" ON ""NotificationCategories"" (""StoreId"");
                ");

                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""NotificationPreferences"" (
                        ""Id"" UUID NOT NULL PRIMARY KEY,
                        ""UserId"" UUID NOT NULL,
                        ""CategoryCode"" VARCHAR(50) NOT NULL,
                        ""IsEnabled"" BOOLEAN NOT NULL DEFAULT TRUE,
                        ""StoreId"" UUID,
                        ""CreatedAt"" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" TIMESTAMP WITHOUT TIME ZONE,
                        ""UpdatedBy"" TEXT,
                        ""CreatedBy"" TEXT
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_NotificationPreferences_User_Category_Store"" ON ""NotificationPreferences"" (""UserId"", ""CategoryCode"", ""StoreId"");
                    CREATE INDEX IF NOT EXISTS ""IX_NotificationPreferences_UserId"" ON ""NotificationPreferences"" (""UserId"");
                ");

                // =============== System Announcements (banner / renewal reminders) ===============
                await context.Database.ExecuteSqlRawAsync(@"
                    CREATE TABLE IF NOT EXISTS ""SystemAnnouncements"" (
                        ""Id"" uuid NOT NULL,
                        ""Title"" character varying(200) NOT NULL,
                        ""Content"" text NOT NULL,
                        ""Kind"" integer NOT NULL,
                        ""Severity"" integer NOT NULL,
                        ""Status"" integer NOT NULL,
                        ""Channels"" integer NOT NULL,
                        ""AudienceJson"" jsonb NOT NULL DEFAULT '{{}}',
                        ""ScheduleAt"" timestamp without time zone,
                        ""ExpiresAt"" timestamp without time zone,
                        ""RequireAck"" boolean NOT NULL DEFAULT false,
                        ""AllowDismiss"" boolean NOT NULL DEFAULT true,
                        ""ImageUrl"" character varying(500),
                        ""ActionUrl"" character varying(500),
                        ""ActionLabel"" character varying(100),
                        ""RecipientCount"" integer NOT NULL DEFAULT 0,
                        ""DeliveredCount"" integer NOT NULL DEFAULT 0,
                        ""SeenCount"" integer NOT NULL DEFAULT 0,
                        ""ClickedCount"" integer NOT NULL DEFAULT 0,
                        ""AckedCount"" integer NOT NULL DEFAULT 0,
                        ""SentAt"" timestamp without time zone,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        CONSTRAINT ""PK_SystemAnnouncements"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_SystemAnnouncements_Status"" ON ""SystemAnnouncements"" (""Status"");
                    CREATE INDEX IF NOT EXISTS ""IX_SystemAnnouncements_ScheduleAt"" ON ""SystemAnnouncements"" (""ScheduleAt"");
                    CREATE INDEX IF NOT EXISTS ""IX_SystemAnnouncements_ExpiresAt"" ON ""SystemAnnouncements"" (""ExpiresAt"");
                    CREATE INDEX IF NOT EXISTS ""IX_SystemAnnouncements_Status_Expires"" ON ""SystemAnnouncements"" (""Status"", ""ExpiresAt"");

                    CREATE TABLE IF NOT EXISTS ""AnnouncementDeliveries"" (
                        ""Id"" uuid NOT NULL,
                        ""AnnouncementId"" uuid NOT NULL,
                        ""UserId"" uuid NOT NULL,
                        ""StoreId"" uuid,
                        ""Channel"" integer NOT NULL,
                        ""Status"" integer NOT NULL,
                        ""DeliveredAt"" timestamp without time zone,
                        ""SeenAt"" timestamp without time zone,
                        ""ClickedAt"" timestamp without time zone,
                        ""AckedAt"" timestamp without time zone,
                        ""DismissedAt"" timestamp without time zone,
                        ""ErrorMessage"" character varying(500),
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        CONSTRAINT ""PK_AnnouncementDeliveries"" PRIMARY KEY (""Id""),
                        CONSTRAINT ""FK_AnnouncementDeliveries_AspNetUsers_UserId""
                            FOREIGN KEY (""UserId"") REFERENCES ""AspNetUsers"" (""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_AnnouncementDeliveries_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores"" (""Id"") ON DELETE SET NULL,
                        CONSTRAINT ""FK_AnnouncementDeliveries_SystemAnnouncements_AnnouncementId""
                            FOREIGN KEY (""AnnouncementId"") REFERENCES ""SystemAnnouncements"" (""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_AnnouncementDeliveries_AnnId"" ON ""AnnouncementDeliveries"" (""AnnouncementId"");
                    CREATE INDEX IF NOT EXISTS ""IX_AnnouncementDeliveries_UserId"" ON ""AnnouncementDeliveries"" (""UserId"");
                    CREATE INDEX IF NOT EXISTS ""IX_AnnouncementDeliveries_StoreId"" ON ""AnnouncementDeliveries"" (""StoreId"");
                    CREATE INDEX IF NOT EXISTS ""IX_AnnouncementDeliveries_User_Status"" ON ""AnnouncementDeliveries"" (""UserId"", ""Status"");
                    CREATE UNIQUE INDEX IF NOT EXISTS ""UX_AnnouncementDeliveries_Ann_User_Channel""
                        ON ""AnnouncementDeliveries"" (""AnnouncementId"", ""UserId"", ""Channel"");
                ");

                // Seed notification categories
                // Ensure CreatedAt has a default (migration-created table may not have one)
                await context.Database.ExecuteSqlRawAsync(@"
                    ALTER TABLE ""NotificationCategories"" ALTER COLUMN ""CreatedAt"" SET DEFAULT NOW();
                ");
                await context.Database.ExecuteSqlRawAsync(@"
                    INSERT INTO ""NotificationCategories"" (""Id"", ""Code"", ""DisplayName"", ""Description"", ""Icon"", ""DisplayOrder"", ""IsSystem"", ""DefaultEnabled"", ""CreatedAt"")
                    VALUES 
                    ('a0000001-0000-0000-0000-000000000001', 'attendance', 'Chấm công', 'Thông báo chấm công vào/ra, trễ giờ, vắng mặt', 'fingerprint', 1, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000002', 'leave', 'Nghỉ phép', 'Đơn nghỉ phép, duyệt/từ chối phép', 'event_busy', 2, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000003', 'overtime', 'Tăng ca', 'Đăng ký tăng ca, duyệt/từ chối tăng ca', 'more_time', 3, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000004', 'payroll', 'Lương & Phiếu lương', 'Phiếu lương, thay đổi lương, thanh toán', 'payments', 4, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000005', 'task', 'Công việc', 'Giao việc, cập nhật tiến độ, deadline', 'task_alt', 5, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000006', 'approval', 'Phê duyệt', 'Yêu cầu phê duyệt, kết quả phê duyệt', 'approval', 6, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000007', 'device', 'Thiết bị', 'Trạng thái máy chấm công online/offline', 'router', 7, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000008', 'hr', 'Nhân sự', 'Hợp đồng, bổ nhiệm, thuyên chuyển', 'people', 8, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000009', 'system', 'Hệ thống', 'Cập nhật hệ thống, bảo trì, thông báo chung', 'settings', 9, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000010', 'kpi', 'KPI', 'Đánh giá KPI, lương KPI, mục tiêu', 'trending_up', 10, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000011', 'internal_comm', 'Truyền thông nội bộ', 'Thông báo nội bộ, tin tức công ty', 'campaign', 11, TRUE, TRUE, NOW())
                    ON CONFLICT DO NOTHING;
                ");
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "An error occurred while initialising the database.");
            throw;
        }
    }

    public async Task SeedAsync()
    {
        try
        {
            await SeedRolesAsync();
            await SeedUsersAsync();
            await SeedEmployeeAsync();
            await SeedShiftTemplatesAsync();
            await SeedHolidaysAsync();
            await SeedPermissionModulesAsync();

            await context.SaveChangesAsync();
            logger.LogInformation("Database seeding completed successfully.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "An error occurred while seeding the database.");
        }
    }

    #region Seed Roles
    
    private async Task SeedRolesAsync()
    {
        var roles = new[] { nameof(Roles.SuperAdmin), nameof(Roles.Admin), nameof(Roles.Director), nameof(Roles.User), nameof(Roles.Manager), nameof(Roles.Employee), nameof(Roles.DepartmentHead), nameof(Roles.Accountant) };

        foreach (var roleName in roles)
        {
            if (!await roleManager.RoleExistsAsync(roleName))
            {
                var role = new IdentityRole<Guid>(roleName);
                await roleManager.CreateAsync(role);
                logger.LogInformation("Created role: {RoleName}", roleName);
            }
        }
    }

    #endregion

    private async Task SeedUsersAsync()
    {
        await SeedSuperAdminAsync();
        await SeedUserAsync(Roles.Admin);
        await SeedUserAsync(Roles.Manager);
        await SeedUserAsync(Roles.Employee);
        await SeedUserAsync(Roles.User);
    }

    private async Task SeedSuperAdminAsync()
    {
        const string email = "sanapos.vn@gmail.com";
        if (await userManager.FindByEmailAsync(email) != null)
        {
            logger.LogInformation("SuperAdmin user already exists.");
            return;
        }

        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            UserName = "superadmin",
            Email = email,
            FirstName = "Super",
            LastName = "Admin",
            Role = nameof(Roles.SuperAdmin),
            EmailConfirmed = true,
            PhoneNumber = "+1234567890",
            PhoneNumberConfirmed = true,
            TwoFactorEnabled = false,
            LockoutEnabled = false,
            AccessFailedCount = 0,
            CreatedAt = DateTime.Now,
            CreatedBy = "System"
        };

        var result = await userManager.CreateAsync(user, "123456aA@");
        if (result.Succeeded)
        {
            await userManager.AddToRoleAsync(user, nameof(Roles.SuperAdmin));
            logger.LogInformation("Created SuperAdmin user: {Email}", email);
        }
        else
        {
            logger.LogError("Failed to create SuperAdmin user: {Errors}", string.Join(", ", result.Errors.Select(e => e.Description)));
        }
    }

    private async Task SeedUserAsync(Roles role)
    {
        var userEmail = role.ToString().ToLower() + "@gmail.com";

        if (await userManager.FindByEmailAsync(userEmail) != null)
        {
            logger.LogInformation("User already exists.");
            return;
        }

        var user = new ApplicationUser
        {
            Id = role == Roles.Manager ? ManagerUserId : Guid.NewGuid(),
            UserName = userEmail.Split("@")[0],
            Email = userEmail,
            FirstName = "System",
            LastName = "" + role.ToString(),
            Role = role.ToString(),
            EmailConfirmed = true,
            PhoneNumber = "+1234567890",
            PhoneNumberConfirmed = true,
            TwoFactorEnabled = true,
            LockoutEnabled = true,
            AccessFailedCount = 0,
            CreatedAt = DateTime.Now,
            CreatedBy = "System"
        };

        var result = await userManager.CreateAsync(user, "Ti100600@");

        if (result.Succeeded)
        {
            await userManager.AddToRoleAsync(user, role.ToString());
            logger.LogInformation("Created user: {Email}", userEmail);
        }
        else
        {
            logger.LogError("Failed to create admin user: {Errors}", string.Join(", ", result.Errors.Select(e => e.Description)));
        }
    }

    private async Task SeedEmployeeAsync()
    {
        var manager = await userManager.FindByIdAsync(ManagerUserId.ToString());
        if (manager == null)
        {
            logger.LogWarning("Manager user not found. Cannot seed employees.");
            return;
        }

        var employees = new List<Employee>
        {
            new Employee
            {
                Id = Guid.NewGuid(),
                EmployeeCode = "EMP001",
                FirstName = "Nguyen Van",
                LastName = "An",
                Gender = "Male",
                DateOfBirth = new DateTime(1990, 5, 15),
                NationalIdNumber = "001234567890",
                NationalIdIssueDate = new DateTime(2015, 6, 1),
                NationalIdIssuePlace = "Ha Noi",
                PhoneNumber = "+84901234567",
                PersonalEmail = "nguyenvanan@gmail.com",
                CompanyEmail = "an.nguyen@company.com",
                PermanentAddress = "123 Nguyen Trai, Thanh Xuan, Ha Noi",
                TemporaryAddress = "123 Nguyen Trai, Thanh Xuan, Ha Noi",
                EmergencyContactName = "Nguyen Van B",
                EmergencyContactPhone = "+84902345678",
                Department = "IT",
                Position = "Senior Developer",
                Level = "Senior",
                JoinDate = new DateTime(2020, 1, 15),
                ProbationEndDate = new DateTime(2020, 3, 15),
                WorkStatus = EmployeeWorkStatus.Active,
                EmploymentType = EmploymentType.Monthly,
                ManagerId = manager.Id,
                CreatedAt = DateTime.Now,
                CreatedBy = "System"
            },
            new Employee
            {
                Id = Guid.NewGuid(),
                EmployeeCode = "EMP002",
                FirstName = "Tran Thi",
                LastName = "Binh",
                Gender = "Female",
                DateOfBirth = new DateTime(1995, 8, 20),
                NationalIdNumber = "001234567891",
                NationalIdIssueDate = new DateTime(2016, 7, 10),
                NationalIdIssuePlace = "Ho Chi Minh",
                PhoneNumber = "+84903456789",
                PersonalEmail = "tranthibinh@gmail.com",
                CompanyEmail = "binh.tran@company.com",
                PermanentAddress = "456 Le Van Viet, Thu Duc, Ho Chi Minh",
                TemporaryAddress = "456 Le Van Viet, Thu Duc, Ho Chi Minh",
                EmergencyContactName = "Tran Van C",
                EmergencyContactPhone = "+84904567890",
                Department = "HR",
                Position = "HR Manager",
                Level = "Lead",
                JoinDate = new DateTime(2019, 6, 1),
                ProbationEndDate = new DateTime(2019, 8, 1),
                WorkStatus = EmployeeWorkStatus.Active,
                EmploymentType = EmploymentType.Monthly,
                ManagerId = manager.Id,
                CreatedAt = DateTime.Now,
                CreatedBy = "System"
            },
            new Employee
            {
                Id = Guid.NewGuid(),
                EmployeeCode = "EMP003",
                FirstName = "Le Minh",
                LastName = "Chau",
                Gender = "Male",
                DateOfBirth = new DateTime(1992, 3, 10),
                NationalIdNumber = "001234567892",
                NationalIdIssueDate = new DateTime(2017, 4, 15),
                NationalIdIssuePlace = "Da Nang",
                PhoneNumber = "+84905678901",
                PersonalEmail = "leminhchau@gmail.com",
                CompanyEmail = "chau.le@company.com",
                PermanentAddress = "789 Tran Phu, Hai Chau, Da Nang",
                TemporaryAddress = "789 Tran Phu, Hai Chau, Da Nang",
                EmergencyContactName = "Le Van D",
                EmergencyContactPhone = "+84906789012",
                Department = "IT",
                Position = "Junior Developer",
                Level = "Junior",
                JoinDate = new DateTime(2022, 9, 1),
                ProbationEndDate = new DateTime(2022, 11, 1),
                WorkStatus = EmployeeWorkStatus.Active,
                EmploymentType = EmploymentType.Monthly,
                ManagerId = manager.Id,
                CreatedAt = DateTime.Now,
                CreatedBy = "System"
            },
            new Employee
            {
                Id = Guid.NewGuid(),
                EmployeeCode = "EMP004",
                FirstName = "Pham Thi",
                LastName = "Dung",
                Gender = "Female",
                DateOfBirth = new DateTime(1988, 12, 5),
                NationalIdNumber = "001234567893",
                NationalIdIssueDate = new DateTime(2014, 5, 20),
                NationalIdIssuePlace = "Ha Noi",
                PhoneNumber = "+84907890123",
                PersonalEmail = "phamthidung@gmail.com",
                CompanyEmail = "dung.pham@company.com",
                PermanentAddress = "321 Giai Phong, Dong Da, Ha Noi",
                TemporaryAddress = "321 Giai Phong, Dong Da, Ha Noi",
                EmergencyContactName = "Pham Van E",
                EmergencyContactPhone = "+84908901234",
                Department = "Finance",
                Position = "Accountant",
                Level = "Senior",
                JoinDate = new DateTime(2018, 3, 15),
                ProbationEndDate = new DateTime(2018, 5, 15),
                WorkStatus = EmployeeWorkStatus.Active,
                EmploymentType = EmploymentType.Monthly,
                ManagerId = manager.Id,
                CreatedAt = DateTime.Now,
                CreatedBy = "System"
            },
            new Employee
            {
                Id = Guid.NewGuid(),
                EmployeeCode = "EMP005",
                FirstName = "Hoang Van",
                LastName = "E",
                Gender = "Male",
                DateOfBirth = new DateTime(1993, 7, 25),
                NationalIdNumber = "001234567894",
                NationalIdIssueDate = new DateTime(2018, 8, 10),
                NationalIdIssuePlace = "Ho Chi Minh",
                PhoneNumber = "+84909012345",
                PersonalEmail = "hoangvane@gmail.com",
                CompanyEmail = "e.hoang@company.com",
                PermanentAddress = "654 Nguyen Hue, Quan 1, Ho Chi Minh",
                TemporaryAddress = "654 Nguyen Hue, Quan 1, Ho Chi Minh",
                EmergencyContactName = "Hoang Thi F",
                EmergencyContactPhone = "+84900123456",
                Department = "Sales",
                Position = "Sales Executive",
                Level = "Junior",
                JoinDate = new DateTime(2021, 11, 1),
                ProbationEndDate = new DateTime(2022, 1, 1),
                WorkStatus = EmployeeWorkStatus.Active,
                EmploymentType = EmploymentType.Hourly,
                ManagerId = manager.Id,
                CreatedAt = DateTime.Now,
                CreatedBy = "System"
            }
        };

        var currentEmployees = await context.Employees.ToListAsync();
        employees = employees.Where(e => !currentEmployees.Any(ce => ce.EmployeeCode == e.EmployeeCode)).ToList();
        await context.Employees.AddRangeAsync(employees);
        logger.LogInformation("Created {Count} default employees", employees.Count);
    }
    #region Seed Shift Templates

    private async Task SeedShiftTemplatesAsync()
    {
        // Check if shift templates already exist
        if (await context.ShiftTemplates.AnyAsync())
        {
            logger.LogInformation("Shift templates already exist. Skipping seed.");
            return;
        }

        // Get the manager user to assign templates to
        var managerEmail = Roles.Manager.ToString().ToLower() + "@gmail.com";
        var manager = await userManager.FindByEmailAsync(managerEmail);

        if (manager == null)
        {
            logger.LogWarning("Manager user not found. Cannot seed shift templates.");
            return;
        }

        var shiftTemplates = new List<ShiftTemplate>
        {
            new ShiftTemplate
            {
                Id = Guid.NewGuid(),
                Name = "Morning Shift (8:00 - 17:00)",
                StartTime = new TimeSpan(8, 0, 0),
                EndTime = new TimeSpan(17, 0, 0),
                MaximumAllowedLateMinutes = 30,
                MaximumAllowedEarlyLeaveMinutes = 30,
                IsActive = true,
                ManagerId = manager.Id,
                CreatedAt = DateTime.Now,
                CreatedBy = "System"
            },
            new ShiftTemplate
            {
                Id = Guid.NewGuid(),
                Name = "Standard Shift (9:00 - 18:00)",
                StartTime = new TimeSpan(9, 0, 0),
                EndTime = new TimeSpan(18, 0, 0),
                MaximumAllowedLateMinutes = 30,
                MaximumAllowedEarlyLeaveMinutes = 30,
                IsActive = true,
                ManagerId = manager.Id,
                CreatedAt = DateTime.Now,
                CreatedBy = "System"
            },
            new ShiftTemplate
            {
                Id = Guid.NewGuid(),
                Name = "Late Morning Shift (10:00 - 19:00)",
                StartTime = new TimeSpan(10, 0, 0),
                EndTime = new TimeSpan(19, 0, 0),
                MaximumAllowedLateMinutes = 30,
                MaximumAllowedEarlyLeaveMinutes = 30,
                IsActive = true,
                ManagerId = manager.Id,
                CreatedAt = DateTime.Now,
                CreatedBy = "System"
            }
        };

        await context.ShiftTemplates.AddRangeAsync(shiftTemplates);
        logger.LogInformation("Created {Count} shift templates", shiftTemplates.Count);
    }

    #endregion

    #region Holidays

    private async Task SeedHolidaysAsync()
    {
        if (await context.Holidays.AnyAsync())
        {
            logger.LogInformation("Holidays already seeded");
            return;
        }

        logger.LogInformation("Seeding Vietnam holidays...");

        var currentYear = DateTime.Now.Year;
        var holidays = VietnamHolidays.GetDefaultHolidays(currentYear);

        // Set audit fields
        foreach (var holiday in holidays)
        {
            holiday.CreatedAt = DateTime.Now;
            holiday.CreatedBy = "System";
        }

        await context.Holidays.AddRangeAsync(holidays);
        await context.SaveChangesAsync();

        logger.LogInformation("Seeded {Count} Vietnam holidays for year {Year}", holidays.Count, currentYear);
    }

    #endregion

    #region Seed Permission Modules

    private async Task SeedPermissionModulesAsync()
    {
        var requiredModules = new (string Module, string DisplayName, string Description, int Order)[]
        {
            // ══════════ TỔNG QUAN ══════════
            ("Home", "Trang chủ", "Màn hình tổng quan menu", 1),
            ("Notification", "Thông báo", "Hệ thống thông báo", 2),
            ("DashboardAttendanceOverview", "Tổng quan chấm công", "KPI chấm công trên Dashboard", 4),
            ("DashboardHrInsights", "Chỉ số nhân sự & vận hành", "Chip chỉ số HR trên Dashboard", 5),
            ("DashboardTodaySchedule", "Lịch làm việc hôm nay", "Lịch ca hôm nay trên Dashboard", 6),
            ("DashboardRealtimeAttendance", "Chấm công thời gian thực", "Danh sách chấm công realtime", 7),
            ("DashboardAbsent", "Nhân viên vắng mặt", "Khối vắng mặt trên Dashboard", 8),
            ("DashboardLateEarly", "Đi trễ / về sớm", "Khối trễ sớm trên Dashboard", 9),
            ("DashboardKpiPanel", "KPI (Dashboard)", "Khối KPI trên Dashboard", 10),
            ("DashboardInternalNews", "Bản tin nội bộ", "Tin truyền thông trên Dashboard", 11),
            // Legacy — giữ để tương thích role cũ (ẩn trên UI Flutter)
            ("Dashboard", "Tổng quan (cũ)", "Bảng điều khiển — dùng các quyền widget bên trên", 3),
            // ══════════ HỒ SƠ NHÂN SỰ ══════════
            ("Employee", "Hồ sơ nhân sự", "Thông tin nhân viên, chức vụ", 4),
            ("DeviceUser", "Nhân sự chấm công", "Nhân sự trên máy chấm công", 5),
            ("Department", "Phòng ban", "Quản lý phòng ban", 6),
            ("Leave", "Nghỉ phép", "Quản lý nghỉ phép", 7),
            ("SalarySettings", "Thiết lập lương", "Cấu hình bảng lương", 8),
            // ══════════ CHẤM CÔNG ══════════
            ("Attendance", "Chấm công thô", "Dữ liệu chấm công thô", 9),
            ("WorkSchedule", "Lịch làm việc", "Phân lịch làm việc", 10),
            ("AttendanceSummary", "Tổng hợp chấm công", "Bảng tổng hợp công theo tháng", 11),
            ("AttendanceByShift", "Tổng hợp chấm công theo ca", "Thống kê giờ công theo ca làm", 12),
            ("AttendanceApproval", "Duyệt chấm công", "Duyệt điều chỉnh chấm công", 13),
            ("ScheduleApproval", "Duyệt lịch làm việc", "Duyệt lịch làm việc đăng ký", 14),
            ("Payroll", "Tổng hợp lương", "Bảng lương nhân viên", 15),
            ("Payslip", "Phiếu lương", "Phiếu lương cá nhân", 15),
            ("Overtime", "Tăng ca", "Đăng ký và duyệt tăng ca", 16),
            ("ShiftSwap", "Đổi ca", "Đổi / đăng ký đổi ca", 17),
            ("AttendanceCorrection", "Chỉnh sửa chấm công", "Yêu cầu chỉnh sửa log chấm công", 18),
            // ══════════ TÀI CHÍNH ══════════
            ("BonusPenalty", "Phiếu thưởng", "Quản lý phiếu thưởng nhân viên", 16),
            ("PenaltyTickets", "Phiếu phạt", "Phiếu phạt tự động từ chấm công", 27),
            ("AdvanceRequests", "Ứng lương", "Quản lý ứng lương", 17),
            ("CashTransaction", "Thu chi", "Quản lý thu chi", 18),
            // ══════════ QUẢN LÝ VẬN HÀNH ══════════
            ("Asset", "Tài sản", "Quản lý tài sản", 19),
            ("Task", "Công việc", "Quản lý công việc", 20),
            ("Communication", "Truyền thông", "Truyền thông nội bộ", 21),
            ("KPI", "KPI", "Đánh giá KPI", 22),
            ("Production", "Sản lượng", "Nhập sản lượng, tính lương sản phẩm", 43),
            ("MobileDeviceRegistration", "Đăng ký chấm công Mobile", "Quản lý đăng ký thiết bị chấm công mobile", 46),
            ("MobileAttendanceApproval", "Duyệt chấm công Mobile", "Duyệt yêu cầu chấm công mobile", 47),
            ("Meal", "Chấm cơm", "Quản lý suất ăn ca", 48),
            ("FieldCheckIn", "Check-in điểm bán", "Quản lý check-in tại điểm bán hàng", 49),
            // ══════════ BÁO CÁO ══════════
            ("AttendanceReport", "Báo cáo chấm công", "Ngày, tháng, đi muộn, phòng ban", 24),
            // ══════════ CÀI ĐẶT ══════════
            ("SettingsHub", "Thiết lập HRM", "Trung tâm cài đặt HRM", 26),
            ("ShiftSetup", "Thiết lập ca", "Ca làm việc, vào sớm, đi trễ, về sớm, tăng ca", 27),
            ("MobileAttendance", "Chấm công Mobile", "Chấm công bằng điện thoại", 28),
            ("Holiday", "Ngày lễ", "Ngày nghỉ lễ, hệ số công", 29),
            ("Device", "Máy chấm công", "Kết nối, quản lý, điều khiển máy chấm công", 30),
            ("Allowance", "Phụ cấp", "Phụ cấp cố định, phụ cấp ngày công", 31),
            ("PenaltySetup", "Phạt", "Đi trễ, về sớm, tái phạm, kỷ luật", 32),
            ("Insurance", "Bảo hiểm", "BHXH, BHYT, BHTN, lương cơ sở", 33),
            ("Tax", "Thuế TNCN", "Bậc thuế, giảm trừ gia cảnh", 34),
            ("UserManagement", "Tài khoản", "Người dùng, kích hoạt, vai trò", 35),
            ("Role", "Phân quyền", "Ma trận quyền, vai trò, module", 36),
            ("SystemSettings", "Hệ thống", "Giờ kết thúc ngày, tham số vận hành", 38),
            ("NotificationSettings", "Thiết lập thông báo", "Nhóm thông báo, bật/tắt nhận thông báo", 39),
            ("GoogleDrive", "Google Drive", "Lưu trữ ảnh, service account", 40),
            ("AIGemini", "Thiết lập AI", "API key, model, tham số AI", 41),
            ("Settings", "Cài đặt", "Cài đặt hệ thống", 42),
            ("ProductSalary", "Lương sản phẩm", "Nhóm sản phẩm, sản phẩm, đơn giá theo bậc", 44),
            ("Feedback", "Phản ánh / Ý kiến", "Phản ánh, góp ý ẩn danh hoặc công khai", 45),
            // ══════════ BÁO CÁO (bổ sung) ══════════
            ("PenaltyReport", "Báo cáo phạt", "Thống kê phiếu phạt, kỷ luật", 50),
            ("AdvanceReport", "Báo cáo ứng lương", "Thống kê ứng lương, tạm ứng", 51),
            ("LeaveReport", "Báo cáo nghỉ phép", "Thống kê nghỉ phép, ngày nghỉ", 52),
            ("CashReport", "Báo cáo thu chi", "Thống kê thu chi tiền mặt", 53),
            ("AssetReport", "Báo cáo tài sản", "Danh mục, cấp phát, lịch sử chuyển giao", 55),
            // ══════════ CÀI ĐẶT (bổ sung) ══════════
            ("DepartmentPermission", "PQ Phòng ban", "Phân quyền theo sơ đồ cây phòng ban", 54),
            // ══════════ API / legacy aliases (ẩn UI Flutter, giữ cho controller) ══════════
            ("Shift", "Ca làm việc (API)", "Đăng ký ca nhân viên", 901),
            ("ShiftTemplate", "Mẫu ca (API)", "Mẫu ca làm việc", 902),
            ("ShiftSalaryLevel", "Bậc lương ca (API)", "Bậc lương theo ca", 903),
            ("Benefit", "Phúc lợi (API)", "Alias Thưởng/Phạt", 904),
            ("Transaction", "Giao dịch (API)", "Alias Thu chi", 905),
            ("BankAccount", "Tài khoản ngân hàng", "Tài khoản ngân hàng thu chi", 906),
            ("Report", "Báo cáo (cũ)", "Alias báo cáo hiện đại", 907),
            ("HrDocument", "Tài liệu HR", "Quản lý tài liệu nhân sự", 908),
            ("OrgChart", "Sơ đồ tổ chức", "Sơ đồ tổ chức công ty", 909),
            ("Geofence", "Vùng chấm công", "Geofence chấm công mobile", 910),
            ("Branch", "Chi nhánh", "Quản lý chi nhánh", 911),
        };

        var existingModules = await context.Permissions.ToListAsync();
        var existingByModule = existingModules.ToDictionary(p => p.Module, p => p);
        var changed = false;

        foreach (var (module, displayName, description, order) in requiredModules)
        {
            if (existingByModule.TryGetValue(module, out var existing))
            {
                if (existing.ModuleDisplayName != displayName || existing.DisplayOrder != order || existing.Description != description)
                {
                    existing.ModuleDisplayName = displayName;
                    existing.Description = description;
                    existing.DisplayOrder = order;
                    changed = true;
                }
            }
            else
            {
                context.Permissions.Add(new Permission
                {
                    Id = Guid.NewGuid(),
                    Module = module,
                    ModuleDisplayName = displayName,
                    Description = description,
                    DisplayOrder = order,
                    CreatedAt = DateTime.Now,
                    CreatedBy = "System"
                });
                changed = true;
                logger.LogInformation("Added permission module: {Module}", module);
            }
        }

        // Remove obsolete modules
        var validModules = requiredModules.Select(m => m.Module).ToHashSet();
        var obsoleteModules = existingModules.Where(p => !validModules.Contains(p.Module)).ToList();
        if (obsoleteModules.Count > 0)
        {
            var obsoleteIds = obsoleteModules.Select(m => m.Id).ToList();
            var orphanedRolePerms = await context.RolePermissions
                .Where(rp => obsoleteIds.Contains(rp.PermissionId))
                .ToListAsync();
            if (orphanedRolePerms.Count > 0)
            {
                context.RolePermissions.RemoveRange(orphanedRolePerms);
                logger.LogInformation("Removed {Count} orphaned RolePermissions", orphanedRolePerms.Count);
            }

            context.Permissions.RemoveRange(obsoleteModules);
            foreach (var m in obsoleteModules)
                logger.LogInformation("Removed obsolete permission module: {Module}", m.Module);
            changed = true;
        }

        if (changed)
        {
            await context.SaveChangesAsync();
            logger.LogInformation("Permission modules synced: {Total} modules", requiredModules.Length);
        }
        else
        {
            logger.LogInformation("Permission modules already up to date ({Count} modules)", requiredModules.Length);
        }

        // Auto-add new modules to existing ServicePackages that have AllowedModules
        var allModuleCodes = requiredModules.Select(m => m.Module).ToList();
        var packages = await context.ServicePackages.ToListAsync();
        foreach (var pkg in packages)
        {
            if (string.IsNullOrEmpty(pkg.AllowedModules)) continue;
            try
            {
                var modules = System.Text.Json.JsonSerializer.Deserialize<List<string>>(pkg.AllowedModules) ?? new List<string>();
                var missing = allModuleCodes.Where(m => !modules.Contains(m)).ToList();
                if (missing.Count > 0)
                {
                    modules.AddRange(missing);
                    pkg.AllowedModules = System.Text.Json.JsonSerializer.Serialize(modules);
                    logger.LogInformation("Added {Count} modules to ServicePackage {Name}: {Modules}",
                        missing.Count, pkg.Name, string.Join(", ", missing));
                }
            }
            catch { /* skip invalid JSON */ }
        }
        await context.SaveChangesAsync();
    }

    #endregion

}
