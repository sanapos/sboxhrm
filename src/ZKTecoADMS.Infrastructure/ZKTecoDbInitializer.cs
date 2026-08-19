using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Helpers;
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

                await context.Database.ExecuteSqlRawAsync(@"
                    ALTER TABLE ""PosStorePrinters"" ADD COLUMN IF NOT EXISTS ""OpenCashDrawer"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosStorePrinters"" ADD COLUMN IF NOT EXISTS ""OpenDrawerCashOnly"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""PosStorePrinters"" ADD COLUMN IF NOT EXISTS ""BeepOnPrint"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosStorePrinters"" ADD COLUMN IF NOT EXISTS ""IsDeviceLocal"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosStorePrinters"" ADD COLUMN IF NOT EXISTS ""OwnerDeviceId"" character varying(64) NULL;
                    ALTER TABLE ""PosStorePrinters"" ADD COLUMN IF NOT EXISTS ""CutPerItem"" boolean NOT NULL DEFAULT false;
                ");

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
                            ALTER TABLE ""AuthorizedMobileDevices"" ADD COLUMN IF NOT EXISTS ""AllowTravelCheckIn"" BOOLEAN NOT NULL DEFAULT false;
                        END IF;
                    END $$;");

                // Add missing columns that are in entities but not in any migration
                await context.Database.ExecuteSqlRawAsync(@"
                    DO $$ BEGIN
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'Holidays') THEN
                            ALTER TABLE ""Holidays"" ADD COLUMN IF NOT EXISTS ""EmployeeIds"" TEXT;
                            ALTER TABLE ""Holidays"" ADD COLUMN IF NOT EXISTS ""SalaryRate"" DOUBLE PRECISION NOT NULL DEFAULT 3.0;
                        END IF;
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'ShiftStaffingQuotas') THEN
                            ALTER TABLE ""ShiftStaffingQuotas"" ADD COLUMN IF NOT EXISTS ""DailyQuotasJson"" TEXT;
                        END IF;
                        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'ShiftTemplates') THEN
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""Description"" TEXT;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""Code"" TEXT;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""EarlyCheckInMinutes"" INTEGER NOT NULL DEFAULT 30;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""LateGraceMinutes"" INTEGER NOT NULL DEFAULT 5;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""EarlyLeaveGraceMinutes"" INTEGER NOT NULL DEFAULT 5;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""OvertimeMinutesThreshold"" INTEGER NOT NULL DEFAULT 30;
                            ALTER TABLE ""ShiftTemplates"" ADD COLUMN IF NOT EXISTS ""EarlyOvertimeMinutesThreshold"" INTEGER NOT NULL DEFAULT 30;
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
                        -- PlainTextPassword: lưu để Super Admin tra cứu mật khẩu
                        ALTER TABLE ""AspNetUsers"" ADD COLUMN IF NOT EXISTS ""PlainTextPassword"" text;

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
                        -- TravelHours/TravelSalary thêm vào entity nhưng thiếu cột thật —
                        -- mọi query chạm bảng Payslips (kể cả gián tiếp qua CashTransactions
                        -- DeleteTransaction) đều lỗi 500 (column p.TravelHours does not exist).
                        ALTER TABLE ""Payslips"" ADD COLUMN IF NOT EXISTS ""TravelHours"" numeric;
                        ALTER TABLE ""Payslips"" ADD COLUMN IF NOT EXISTS ""TravelSalary"" numeric;

                        -- Gán khu vực bàn/phòng theo tài khoản POS (Order chỉ thấy khu được chia).
                        CREATE TABLE IF NOT EXISTS ""PosServiceAreaAssignments"" (
                            ""Id"" uuid NOT NULL PRIMARY KEY,
                            ""StoreId"" uuid NOT NULL,
                            ""UserId"" uuid NOT NULL,
                            ""AreaId"" uuid NOT NULL,
                            ""CanView"" boolean NOT NULL DEFAULT TRUE,
                            ""CanOperate"" boolean NOT NULL DEFAULT TRUE,
                            ""IsActive"" boolean NOT NULL DEFAULT TRUE,
                            ""GrantedBy"" character varying(100),
                            ""Note"" character varying(500),
                            ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                            ""UpdatedAt"" timestamp without time zone,
                            ""CreatedBy"" text,
                            ""UpdatedBy"" text
                        );
                        CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosServiceAreaAssignments_Store_User_Area""
                            ON ""PosServiceAreaAssignments"" (""StoreId"", ""UserId"", ""AreaId"");
                        CREATE INDEX IF NOT EXISTS ""IX_PosServiceAreaAssignments_Store_User""
                            ON ""PosServiceAreaAssignments"" (""StoreId"", ""UserId"");

                        -- TransactionCode được sinh đếm theo StoreId (mỗi store tự đếm phiếu thu/chi
                        -- trong ngày của mình), nhưng unique index cũ lại là GLOBAL trên toàn bộ bảng
                        -- -- 2 store khác nhau tạo phiếu cùng ngày dễ ra cùng mã (VD TH-20260721-0001)
                        -- -- lỗi 500 duplicate key khi tạo hóa đơn bán/phiếu thu chi. Đổi sang unique
                        -- composite (StoreId, TransactionCode) đúng với cách sinh mã hiện tại.
                        -- Partial (Deleted IS NULL): phiếu thu/chi bị soft-delete vẫn chiếm số cũ
                        -- trong bảng nhưng GenerateCodeAsync đếm qua EF (có global filter ẩn bản ghi
                        -- đã xóa) nên cứ đoán lại đúng số đã xóa đó — số đó bị chặn vĩnh viễn,
                        -- sinh đơn bán/thu chi mới luôn trùng mã 23505 dù đã retry nhiều lần.
                        DROP INDEX IF EXISTS ""IX_CashTransactions_TransactionCode"";
                        DROP INDEX IF EXISTS ""IX_CashTransactions_StoreId_TransactionCode"";
                        CREATE UNIQUE INDEX IF NOT EXISTS ""IX_CashTransactions_StoreId_TransactionCode""
                            ON ""CashTransactions"" (""StoreId"", ""TransactionCode"")
                            WHERE ""Deleted"" IS NULL;

                        -- Slot hóa đơn tạm TMP-nn được tái sử dụng sau khi đơn cũ bị soft-delete
                        -- (EnsureInvoiceSlotsAsync tạo lại slot rỗng mỗi lần poll), nhưng unique
                        -- index cũ trên (StoreId, OrderNo) tính luôn cả bản ghi đã xóa — 1 đơn TMP
                        -- bị xóa trước đó chặn vĩnh viễn việc tái tạo slot đó (lỗi duplicate key
                        -- lặp lại liên tục mỗi lần poll invoice-slots). Đổi sang partial unique
                        -- index chỉ áp cho các đơn còn sống.
                        DROP INDEX IF EXISTS ""IX_PosSaleOrders_StoreId_OrderNo"";
                        CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosSaleOrders_StoreId_OrderNo""
                            ON ""PosSaleOrders"" (""StoreId"", ""OrderNo"")
                            WHERE ""Deleted"" IS NULL;

                        -- Cùng lỗi TransactionCode: TransferCode phiếu chuyển quỹ sinh đếm theo
                        -- StoreId nhưng unique index cũ là GLOBAL trên toàn bảng. Partial để nhất
                        -- quán với CashTransactions/PosSaleOrders.
                        DROP INDEX IF EXISTS ""IX_FundTransfers_TransferCode"";
                        DROP INDEX IF EXISTS ""IX_FundTransfers_StoreId_TransferCode"";
                        CREATE UNIQUE INDEX IF NOT EXISTS ""IX_FundTransfers_StoreId_TransferCode""
                            ON ""FundTransfers"" (""StoreId"", ""TransferCode"")
                            WHERE ""Deleted"" IS NULL;

                        CREATE TABLE IF NOT EXISTS ""PayslipAttendanceSnapshots"" (
                            ""Id"" uuid NOT NULL PRIMARY KEY,
                            ""PayslipId"" uuid NOT NULL,
                            ""StoreId"" uuid NULL,
                            ""PeriodStart"" timestamp without time zone NOT NULL,
                            ""PeriodEnd"" timestamp without time zone NOT NULL,
                            ""SnapshotJson"" text NOT NULL,
                            ""CapturedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                            ""CapturedByUserId"" uuid NULL
                        );
                        CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PayslipAttendanceSnapshots_PayslipId""
                            ON ""PayslipAttendanceSnapshots"" (""PayslipId"");

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

                    CREATE TABLE IF NOT EXISTS ""PosProductCategories"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ParentId"" uuid,
                        ""Name"" character varying(200) NOT NULL DEFAULT '',
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosProductCategories_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProductCategories_Parent""
                            FOREIGN KEY (""ParentId"") REFERENCES ""PosProductCategories""(""Id"") ON DELETE RESTRICT
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductCategories_StoreId_Name"" ON ""PosProductCategories""(""StoreId"", ""Name"");

                    CREATE TABLE IF NOT EXISTS ""PosProductBrands"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""Name"" character varying(200) NOT NULL DEFAULT '',
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosProductBrands_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductBrands_StoreId_Name"" ON ""PosProductBrands""(""StoreId"", ""Name"");

                    CREATE TABLE IF NOT EXISTS ""PosStorageLocations"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""Name"" character varying(200) NOT NULL DEFAULT '',
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosStorageLocations_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosStorageLocations_StoreId_Name"" ON ""PosStorageLocations""(""StoreId"", ""Name"");

                    CREATE TABLE IF NOT EXISTS ""PosProducts"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ProductCode"" character varying(50) NOT NULL DEFAULT '',
                        ""Barcode"" character varying(50),
                        ""Name"" character varying(500) NOT NULL DEFAULT '',
                        ""CategoryId"" uuid,
                        ""BrandId"" uuid,
                        ""StorageLocationId"" uuid,
                        ""ProductType"" integer NOT NULL DEFAULT 0,
                        ""Description"" character varying(2000),
                        ""ImageUrl"" character varying(500),
                        ""CostPrice"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""BasePrice"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""OnHandQty"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""ReservedQty"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""MinStockQty"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""MaxStockQty"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""Weight"" numeric(18,4),
                        ""WeightUnit"" character varying(20) NOT NULL DEFAULT 'g',
                        ""BaseUnitName"" character varying(100) NOT NULL DEFAULT 'Cái',
                        ""IsDirectSale"" boolean NOT NULL DEFAULT true,
                        ""IsFavorite"" boolean NOT NULL DEFAULT false,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosProducts_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProducts_Category""
                            FOREIGN KEY (""CategoryId"") REFERENCES ""PosProductCategories""(""Id"") ON DELETE SET NULL,
                        CONSTRAINT ""FK_PosProducts_Brand""
                            FOREIGN KEY (""BrandId"") REFERENCES ""PosProductBrands""(""Id"") ON DELETE SET NULL,
                        CONSTRAINT ""FK_PosProducts_StorageLocation""
                            FOREIGN KEY (""StorageLocationId"") REFERENCES ""PosStorageLocations""(""Id"") ON DELETE SET NULL
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosProducts_StoreId_ProductCode"" ON ""PosProducts""(""StoreId"", ""ProductCode"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosProducts_StoreId_Name"" ON ""PosProducts""(""StoreId"", ""Name"");

                    CREATE TABLE IF NOT EXISTS ""PosProductUnits"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ProductId"" uuid NOT NULL,
                        ""UnitName"" character varying(100) NOT NULL DEFAULT '',
                        ""ConversionRate"" numeric(18,4) NOT NULL DEFAULT 1,
                        ""BasePrice"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""IsDirectSale"" boolean NOT NULL DEFAULT true,
                        ""IsBaseUnit"" boolean NOT NULL DEFAULT false,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosProductUnits_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProductUnits_Product""
                            FOREIGN KEY (""ProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductUnits_ProductId_UnitName"" ON ""PosProductUnits""(""ProductId"", ""UnitName"");

                    CREATE TABLE IF NOT EXISTS ""PosSuppliers"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""Name"" character varying(200) NOT NULL DEFAULT '',
                        ""Phone"" character varying(50),
                        ""Email"" character varying(200),
                        ""Address"" character varying(500),
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosSuppliers_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosSuppliers_StoreId_Name"" ON ""PosSuppliers""(""StoreId"", ""Name"");

                    CREATE TABLE IF NOT EXISTS ""PosProductAttributes"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""Name"" character varying(100) NOT NULL DEFAULT '',
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosProductAttributes_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductAttributes_StoreId_Name"" ON ""PosProductAttributes""(""StoreId"", ""Name"");

                    CREATE TABLE IF NOT EXISTS ""PosProductAttributeValues"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ProductId"" uuid NOT NULL,
                        ""AttributeId"" uuid NOT NULL,
                        ""Value"" character varying(500) NOT NULL DEFAULT '',
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosProductAttributeValues_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProductAttributeValues_Product""
                            FOREIGN KEY (""ProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProductAttributeValues_Attribute""
                            FOREIGN KEY (""AttributeId"") REFERENCES ""PosProductAttributes""(""Id"") ON DELETE CASCADE
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosProductAttributeValues_ProductId_AttributeId"" ON ""PosProductAttributeValues""(""ProductId"", ""AttributeId"");

                    CREATE TABLE IF NOT EXISTS ""PosStockTransactions"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ProductId"" uuid NOT NULL,
                        ""TransactionType"" integer NOT NULL DEFAULT 0,
                        ""QtyChange"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""QtyAfter"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""ReferenceNo"" character varying(50),
                        ""Note"" character varying(500),
                        ""SaleOrderId"" uuid,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosStockTransactions_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosStockTransactions_Product""
                            FOREIGN KEY (""ProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosStockTransactions_StoreId_ProductId_CreatedAt"" ON ""PosStockTransactions""(""StoreId"", ""ProductId"", ""CreatedAt"");

                    CREATE TABLE IF NOT EXISTS ""PosSaleOrders"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""OrderNo"" character varying(30) NOT NULL DEFAULT '',
                        ""Status"" integer NOT NULL DEFAULT 1,
                        ""SubTotal"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""Discount"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""Total"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""PaidAmount"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""PaymentMethod"" character varying(50) NOT NULL DEFAULT 'Tiền mặt',
                        ""CustomerName"" character varying(200),
                        ""Note"" character varying(500),
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosSaleOrders_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosSaleOrders_StoreId_OrderNo"" ON ""PosSaleOrders""(""StoreId"", ""OrderNo"");

                    CREATE TABLE IF NOT EXISTS ""PosSaleOrderLines"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""SaleOrderId"" uuid NOT NULL,
                        ""ProductId"" uuid NOT NULL,
                        ""ProductName"" character varying(500) NOT NULL DEFAULT '',
                        ""UnitName"" character varying(100),
                        ""Qty"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""UnitPrice"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""LineTotal"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosSaleOrderLines_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosSaleOrderLines_SaleOrder""
                            FOREIGN KEY (""SaleOrderId"") REFERENCES ""PosSaleOrders""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosSaleOrderLines_Product""
                            FOREIGN KEY (""ProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE RESTRICT
                    );

                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""SaleQuickNotesJson"" character varying(4000);
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""VatRate"" numeric(5,2) NOT NULL DEFAULT 8;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""VatExempt"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""SupplierId"" uuid;
                    DO $$ BEGIN
                        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosProducts_Supplier') THEN
                            ALTER TABLE ""PosProducts""
                                ADD CONSTRAINT ""FK_PosProducts_Supplier""
                                FOREIGN KEY (""SupplierId"") REFERENCES ""PosSuppliers""(""Id"") ON DELETE SET NULL;
                        END IF;
                    END $$;

                    CREATE TABLE IF NOT EXISTS ""PosProductComboLines"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ComboProductId"" uuid NOT NULL,
                        ""ComponentProductId"" uuid NOT NULL,
                        ""Qty"" numeric(18,4) NOT NULL DEFAULT 1,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosProductComboLines_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProductComboLines_Combo""
                            FOREIGN KEY (""ComboProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProductComboLines_Component""
                            FOREIGN KEY (""ComponentProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE RESTRICT
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosProductComboLines_Combo_Component"" ON ""PosProductComboLines""(""ComboProductId"", ""ComponentProductId"");

                    CREATE TABLE IF NOT EXISTS ""PosStockReceipts"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ReceiptNo"" character varying(30) NOT NULL DEFAULT '',
                        ""SupplierId"" uuid,
                        ""Note"" character varying(500),
                        ""TotalQty"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""TotalCost"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosStockReceipts_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosStockReceipts_Supplier""
                            FOREIGN KEY (""SupplierId"") REFERENCES ""PosSuppliers""(""Id"") ON DELETE SET NULL
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosStockReceipts_StoreId_ReceiptNo"" ON ""PosStockReceipts""(""StoreId"", ""ReceiptNo"");

                    CREATE TABLE IF NOT EXISTS ""PosStockReceiptLines"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ReceiptId"" uuid NOT NULL,
                        ""ProductId"" uuid NOT NULL,
                        ""ProductName"" character varying(500) NOT NULL DEFAULT '',
                        ""ProductCode"" character varying(50),
                        ""Qty"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""CostPrice"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""LineTotal"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosStockReceiptLines_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosStockReceiptLines_Receipt""
                            FOREIGN KEY (""ReceiptId"") REFERENCES ""PosStockReceipts""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosStockReceiptLines_Product""
                            FOREIGN KEY (""ProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE RESTRICT
                    );

                    ALTER TABLE ""PosStockTransactions"" ADD COLUMN IF NOT EXISTS ""StockReceiptId"" uuid;
                    ALTER TABLE ""PosStockTransactions"" ADD COLUMN IF NOT EXISTS ""VariantId"" uuid;
                    ALTER TABLE ""PosStockReceiptLines"" ADD COLUMN IF NOT EXISTS ""VariantId"" uuid;

                    CREATE TABLE IF NOT EXISTS ""PosProductVariants"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ProductId"" uuid NOT NULL,
                        ""SkuCode"" character varying(50) NOT NULL DEFAULT '',
                        ""Barcode"" character varying(50),
                        ""Name"" character varying(500) NOT NULL DEFAULT '',
                        ""AttributeJson"" character varying(2000),
                        ""CostPrice"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""BasePrice"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""OnHandQty"" numeric(18,4) NOT NULL DEFAULT 0,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosProductVariants_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProductVariants_Product""
                            FOREIGN KEY (""ProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE CASCADE
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosProductVariants_ProductId_SkuCode"" ON ""PosProductVariants""(""ProductId"", ""SkuCode"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductVariants_StoreId_Barcode"" ON ""PosProductVariants""(""StoreId"", ""Barcode"");

                    ALTER TABLE ""PosSaleOrderLines"" ADD COLUMN IF NOT EXISTS ""VariantId"" uuid NULL;
                    DO $$ BEGIN
                        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_PosSaleOrderLines_Variant') THEN
                            ALTER TABLE ""PosSaleOrderLines""
                                ADD CONSTRAINT ""FK_PosSaleOrderLines_Variant""
                                FOREIGN KEY (""VariantId"") REFERENCES ""PosProductVariants""(""Id"") ON DELETE SET NULL;
                        END IF;
                    END $$;

                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""SoldByEmployeeId"" uuid NULL;

                    CREATE TABLE IF NOT EXISTS ""PosPriceLists"" (
                        ""Id"" uuid PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""Name"" character varying(100) NOT NULL,
                        ""IsDefault"" boolean NOT NULL DEFAULT false,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosPriceLists_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosPriceLists_StoreId_Name""
                        ON ""PosPriceLists""(""StoreId"", ""Name"");

                    CREATE TABLE IF NOT EXISTS ""PosPriceListItems"" (
                        ""Id"" uuid PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""PriceListId"" uuid NOT NULL,
                        ""ProductId"" uuid NOT NULL,
                        ""VariantId"" uuid NULL,
                        ""UnitId"" uuid NULL,
                        ""Price"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosPriceListItems_PriceList""
                            FOREIGN KEY (""PriceListId"") REFERENCES ""PosPriceLists""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosPriceListItems_Product""
                            FOREIGN KEY (""ProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosPriceListItems_PriceList_Product""
                        ON ""PosPriceListItems""(""PriceListId"", ""ProductId"", ""VariantId"", ""UnitId"");

                    ALTER TABLE ""PosPriceLists"" ADD COLUMN IF NOT EXISTS ""ValidFrom"" timestamp without time zone NULL;
                    ALTER TABLE ""PosPriceLists"" ADD COLUMN IF NOT EXISTS ""ValidTo"" timestamp without time zone NULL;

                    -- Item cũ tạo lúc IsActive mặc định false → không hiện khi đọc lại.
                    UPDATE ""PosPriceListItems"" SET ""IsActive"" = true
                    WHERE ""Deleted"" IS NULL AND ""IsActive"" = false;

                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""PriceListId"" uuid NULL;

                    -- Floor map ops
                    ALTER TABLE ""PosServiceResources"" ADD COLUMN IF NOT EXISTS ""LayoutX"" double precision NULL;
                    ALTER TABLE ""PosServiceResources"" ADD COLUMN IF NOT EXISTS ""LayoutY"" double precision NULL;
                    ALTER TABLE ""PosServiceResources"" ADD COLUMN IF NOT EXISTS ""LayoutW"" double precision NOT NULL DEFAULT 120;
                    ALTER TABLE ""PosServiceResources"" ADD COLUMN IF NOT EXISTS ""LayoutH"" double precision NOT NULL DEFAULT 100;
                    ALTER TABLE ""PosServiceResources"" ADD COLUMN IF NOT EXISTS ""NeedsCleaning"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosResourceSessions"" ADD COLUMN IF NOT EXISTS ""AccumulatedPauseMinutes"" integer NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosResourceSessions"" ADD COLUMN IF NOT EXISTS ""GuestCount"" integer NOT NULL DEFAULT 1;
                    ALTER TABLE ""PosResourceSessions"" ADD COLUMN IF NOT EXISTS ""BillRequested"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosSaleOrderLines"" ADD COLUMN IF NOT EXISTS ""UnitId"" uuid NULL;
                    ALTER TABLE ""PosSaleOrderLines"" ADD COLUMN IF NOT EXISTS ""KitchenSentQty"" numeric(18,3) NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosSaleOrderLines"" ADD COLUMN IF NOT EXISTS ""KitchenSentAt"" timestamp without time zone NULL;
                    ALTER TABLE ""PosSaleOrderLines"" ADD COLUMN IF NOT EXISTS ""KitchenDoneQty"" numeric(18,3) NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosSaleOrderLines"" ADD COLUMN IF NOT EXISTS ""KitchenPrepStatus"" character varying(20) NOT NULL DEFAULT 'none';
                    ALTER TABLE ""PosCustomers"" ADD COLUMN IF NOT EXISTS ""Birthday"" timestamp without time zone NULL;
                    ALTER TABLE ""PosCustomers"" ADD COLUMN IF NOT EXISTS ""DeliveryAddress"" character varying(500);

                    -- Tách NVL / Topping thành ProductType riêng (3 / 4). Topping trước, rồi hàng ẩn POS.
                    UPDATE ""PosProducts"" SET ""ProductType"" = 4
                    WHERE ""Deleted"" IS NULL AND ""ProductType"" = 0 AND ""IsTopping"" = true;
                    UPDATE ""PosProducts"" SET ""ProductType"" = 3, ""IsDirectSale"" = false, ""IsTopping"" = false
                    WHERE ""Deleted"" IS NULL AND ""ProductType"" = 0 AND ""IsDirectSale"" = false AND ""IsTopping"" = false;
                    CREATE INDEX IF NOT EXISTS ""IX_PosProducts_StoreId_ProductType""
                        ON ""PosProducts"" (""StoreId"", ""ProductType"");

                    CREATE TABLE IF NOT EXISTS ""PosProductRecipeLines"" (
                        ""Id"" uuid NOT NULL PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ParentProductId"" uuid NOT NULL,
                        ""ComponentProductId"" uuid NOT NULL,
                        ""Qty"" numeric(18,4) NOT NULL DEFAULT 1,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text,
                        CONSTRAINT ""FK_PosProductRecipeLines_Stores_StoreId""
                            FOREIGN KEY (""StoreId"") REFERENCES ""Stores""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProductRecipeLines_Parent""
                            FOREIGN KEY (""ParentProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE CASCADE,
                        CONSTRAINT ""FK_PosProductRecipeLines_Component""
                            FOREIGN KEY (""ComponentProductId"") REFERENCES ""PosProducts""(""Id"") ON DELETE RESTRICT
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductRecipeLines_Parent""
                        ON ""PosProductRecipeLines""(""ParentProductId"");
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosProductRecipeLines_Parent_Component_Active""
                        ON ""PosProductRecipeLines""(""ParentProductId"", ""ComponentProductId"")
                        WHERE ""Deleted"" IS NULL;
                    ALTER TABLE ""PosSaleOrderLines"" ADD COLUMN IF NOT EXISTS ""ToppingsJson"" text NULL;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""IsTopping"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""AllowToppings"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""AutoOpenToppingPopup"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""ShowComboComponentsOnSell"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""AllowDecimalQty"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosPrintTemplates"" ADD COLUMN IF NOT EXISTS ""SourceCatalogId"" uuid NULL;
                    CREATE TABLE IF NOT EXISTS ""PosPrintTemplateCatalogs"" (
                        ""Id"" uuid PRIMARY KEY,
                        ""Name"" character varying(120) NOT NULL,
                        ""DocumentType"" integer NOT NULL DEFAULT 1,
                        ""PaperSize"" integer NOT NULL DEFAULT 1,
                        ""HtmlContent"" text NOT NULL DEFAULT '',
                        ""IsRecommended"" boolean NOT NULL DEFAULT false,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone,
                        ""UpdatedBy"" text,
                        ""CreatedBy"" text,
                        ""LastModified"" timestamp without time zone,
                        ""LastModifiedBy"" text,
                        ""Deleted"" timestamp without time zone,
                        ""DeletedBy"" text
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosPrintTemplateCatalogs_DocumentType_Sort""
                        ON ""PosPrintTemplateCatalogs"" (""DocumentType"", ""SortOrder"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosPrintTemplates_SourceCatalogId""
                        ON ""PosPrintTemplates"" (""SourceCatalogId"");
                    ALTER TABLE ""PosStoreSellSettings"" ADD COLUMN IF NOT EXISTS ""AllowProvisionalBill"" boolean NOT NULL DEFAULT false;
                    DO $$
                    BEGIN
                        IF NOT EXISTS (
                            SELECT 1 FROM information_schema.columns
                            WHERE table_name = 'PosStoreSellSettings'
                              AND column_name = 'EnableMultiDeviceDraftLock'
                        ) THEN
                            ALTER TABLE ""PosStoreSellSettings""
                                ADD COLUMN ""EnableMultiDeviceDraftLock"" boolean NOT NULL DEFAULT false;
                            -- Backfill 1 lần: cửa hàng sơ đồ/bàn giữ hành vi khóa đa máy cũ.
                            UPDATE ""PosStoreSellSettings""
                            SET ""EnableMultiDeviceDraftLock"" = true
                            WHERE ""Deleted"" IS NULL
                              AND (""ShowFloorPlan"" = true OR ""EnableResources"" = true);
                        END IF;
                    END $$;
                    ALTER TABLE ""PosStoreSellSettings"" ADD COLUMN IF NOT EXISTS ""PromptGuestCountOnOpen"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosStoreSellSettings"" ADD COLUMN IF NOT EXISTS ""AllowNegativeStock"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosStoreSellSettings"" ADD COLUMN IF NOT EXISTS ""EnableCashierShift"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosStoreSellSettings"" ADD COLUMN IF NOT EXISTS ""EnableQrTableOrder"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosStoreSellSettings"" ADD COLUMN IF NOT EXISTS ""EnableQrOrderAutoPrint"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""PosServiceResources"" ADD COLUMN IF NOT EXISTS ""QrOrderToken"" character varying(32) NULL;
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosServiceResources_QrOrderToken""
                        ON ""PosServiceResources"" (""QrOrderToken"")
                        WHERE ""QrOrderToken"" IS NOT NULL AND ""Deleted"" IS NULL;
                    CREATE TABLE IF NOT EXISTS ""PosCashierShifts"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""OpenedAt"" timestamp without time zone NOT NULL,
                        ""OpenedByUserId"" uuid NULL,
                        ""OpenedByName"" character varying(200) NULL,
                        ""OpeningCash"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""ClosedAt"" timestamp without time zone NULL,
                        ""ClosedByUserId"" uuid NULL,
                        ""ClosedByName"" character varying(200) NULL,
                        ""CountedCash"" numeric(18,2) NULL,
                        ""ExpectedCash"" numeric(18,2) NULL,
                        ""Difference"" numeric(18,2) NULL,
                        ""Note"" character varying(500) NULL,
                        ""Status"" character varying(20) NOT NULL DEFAULT 'Open',
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL,
                        ""CreatedBy"" character varying(200) NULL,
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" character varying(200) NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" character varying(200) NULL,
                        CONSTRAINT ""PK_PosCashierShifts"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosCashierShifts_Store_Status""
                        ON ""PosCashierShifts"" (""StoreId"", ""Status"");
                    UPDATE ""PosCashierShifts"" AS s
                    SET ""Status"" = 'Closed',
                        ""ClosedAt"" = COALESCE(s.""ClosedAt"", NOW()),
                        ""UpdatedAt"" = NOW()
                    FROM (
                        SELECT ""Id"" FROM (
                            SELECT ""Id"",
                                   ROW_NUMBER() OVER (
                                       PARTITION BY ""StoreId""
                                       ORDER BY ""OpenedAt"" DESC NULLS LAST, ""Id"" DESC) AS rn
                            FROM ""PosCashierShifts""
                            WHERE ""Status"" = 'Open' AND ""Deleted"" IS NULL
                        ) ranked WHERE rn > 1
                    ) extra
                    WHERE s.""Id"" = extra.""Id"";
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosCashierShifts_Store_OneOpen""
                        ON ""PosCashierShifts"" (""StoreId"")
                        WHERE ""Status"" = 'Open' AND ""Deleted"" IS NULL;
                    ALTER TABLE ""PosStoreSellSettings"" ADD COLUMN IF NOT EXISTS ""DefaultHourlyProductId"" uuid NULL;
                    ALTER TABLE ""PosServiceResources"" ADD COLUMN IF NOT EXISTS ""DefaultServiceProductId"" uuid NULL;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""GraceMinutes"" integer NULL;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""RoundAfterMinutes"" integer NULL;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""OpeningFee"" numeric(18,2) NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""OpeningMinutes"" integer NULL;
                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""SessionPackValidDays"" integer NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""VatAmount"" numeric(18,2) NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""SplitFromOrderId"" uuid NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceStatus"" character varying(20) NOT NULL DEFAULT 'None';
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceProvider"" character varying(20) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceTransactionUuid"" character varying(36) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceNo"" character varying(30) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceSeries"" character varying(25) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceReservationCode"" character varying(50) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceCode"" character varying(50) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceIssuedAt"" timestamp without time zone NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceError"" character varying(1000) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceBuyerName"" character varying(200) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceBuyerCompanyName"" character varying(200) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceBuyerTaxCode"" character varying(50) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceBuyerAddress"" character varying(500) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceBuyerEmail"" character varying(200) NULL;
                    ALTER TABLE ""PosSaleOrders"" ADD COLUMN IF NOT EXISTS ""EInvoiceBuyerPhone"" character varying(50) NULL;
                    CREATE INDEX IF NOT EXISTS ""IX_PosSaleOrders_Store_EInvoiceStatus""
                        ON ""PosSaleOrders"" (""StoreId"", ""EInvoiceStatus"");

                    CREATE TABLE IF NOT EXISTS ""PosEInvoiceSettings"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""Enabled"" boolean NOT NULL DEFAULT false,
                        ""Provider"" character varying(20) NOT NULL DEFAULT 'Viettel',
                        ""ApiBaseUrl"" character varying(300) NOT NULL DEFAULT 'https://api-vinvoice.viettel.vn',
                        ""Username"" character varying(100) NOT NULL DEFAULT '',
                        ""Password"" character varying(200) NOT NULL DEFAULT '',
                        ""SupplierTaxCode"" character varying(20) NOT NULL DEFAULT '',
                        ""TemplateCode"" character varying(20) NOT NULL DEFAULT '1/001',
                        ""InvoiceSeries"" character varying(25) NOT NULL DEFAULT '',
                        ""InvoiceType"" character varying(10) NOT NULL DEFAULT '1',
                        ""AskAtCheckout"" boolean NOT NULL DEFAULT true,
                        ""DefaultIssueAtCheckout"" boolean NOT NULL DEFAULT false,
                        ""TaxMode"" character varying(20) NOT NULL DEFAULT 'included',
                        ""DefaultTaxPercent"" numeric(18,2) NOT NULL DEFAULT 10,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosEInvoiceSettings"" PRIMARY KEY (""Id"")
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosEInvoiceSettings_StoreId""
                        ON ""PosEInvoiceSettings"" (""StoreId"");

                    CREATE TABLE IF NOT EXISTS ""PosBarcodeCatalog"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""Barcode"" character varying(50) NOT NULL,
                        ""Name"" character varying(500) NOT NULL,
                        ""UnitName"" character varying(100) NULL,
                        ""BrandName"" character varying(200) NULL,
                        ""CategoryName"" character varying(200) NULL,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosBarcodeCatalog"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosBarcodeCatalog_Store_Barcode""
                        ON ""PosBarcodeCatalog"" (""StoreId"", ""Barcode"");
                    ALTER TABLE ""PosBarcodeCatalog"" ADD COLUMN IF NOT EXISTS ""ImageUrl"" character varying(1000) NULL;

                    CREATE TABLE IF NOT EXISTS ""PosProductSampleCatalog"" (
                        ""Id"" uuid NOT NULL,
                        ""Barcode"" character varying(50) NULL,
                        ""Name"" character varying(500) NOT NULL,
                        ""UnitName"" character varying(100) NULL,
                        ""BrandName"" character varying(200) NULL,
                        ""CategoryName"" character varying(200) NULL,
                        ""ImageUrl"" character varying(1000) NULL,
                        ""Description"" character varying(2000) NULL,
                        ""Kind"" integer NOT NULL DEFAULT 0,
                        ""ProductType"" integer NOT NULL DEFAULT 0,
                        ""DefaultPrice"" numeric(18,2) NULL,
                        ""DefaultCostPrice"" numeric(18,2) NULL,
                        ""VatRate"" numeric(9,4) NOT NULL DEFAULT 8,
                        ""VatExempt"" boolean NOT NULL DEFAULT false,
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosProductSampleCatalog"" PRIMARY KEY (""Id"")
                    );
                    ALTER TABLE ""PosProductSampleCatalog"" ADD COLUMN IF NOT EXISTS ""Description"" character varying(2000) NULL;
                    ALTER TABLE ""PosProductSampleCatalog"" ADD COLUMN IF NOT EXISTS ""DefaultCostPrice"" numeric(18,2) NULL;
                    ALTER TABLE ""PosProductSampleCatalog"" ADD COLUMN IF NOT EXISTS ""VatRate"" numeric(9,4) NOT NULL DEFAULT 8;
                    ALTER TABLE ""PosProductSampleCatalog"" ADD COLUMN IF NOT EXISTS ""VatExempt"" boolean NOT NULL DEFAULT false;
                    ALTER TABLE ""PosProductSampleCatalog"" ADD COLUMN IF NOT EXISTS ""SellProfiles"" character varying(200) NULL;
                    ALTER TABLE ""PosProductSampleCatalog"" ADD COLUMN IF NOT EXISTS ""ServiceBillingMode"" integer NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosProductSampleCatalog"" ADD COLUMN IF NOT EXISTS ""SessionPackCount"" integer NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosProductSampleCatalog"" ADD COLUMN IF NOT EXISTS ""SessionPackValidDays"" integer NOT NULL DEFAULT 0;
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductSampleCatalog_Barcode""
                        ON ""PosProductSampleCatalog"" (""Barcode"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductSampleCatalog_Kind_Sort""
                        ON ""PosProductSampleCatalog"" (""Kind"", ""SortOrder"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductSampleCatalog_ProductType""
                        ON ""PosProductSampleCatalog"" (""ProductType"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductSampleCatalog_Name""
                        ON ""PosProductSampleCatalog"" (""Name"");

                    CREATE TABLE IF NOT EXISTS ""PosProductSampleCategory"" (
                        ""Id"" uuid NOT NULL,
                        ""Name"" character varying(200) NOT NULL,
                        ""ParentId"" uuid NULL,
                        ""Kind"" integer NULL,
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosProductSampleCategory"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductSampleCategory_Name""
                        ON ""PosProductSampleCategory"" (""Name"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductSampleCategory_Kind_Sort""
                        ON ""PosProductSampleCategory"" (""Kind"", ""SortOrder"");
                    ALTER TABLE ""PosProductSampleCatalog"" ADD COLUMN IF NOT EXISTS ""CategoryId"" uuid NULL;
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductSampleCatalog_CategoryId""
                        ON ""PosProductSampleCatalog"" (""CategoryId"");

                    ALTER TABLE ""ServicePackages"" ADD COLUMN IF NOT EXISTS ""MaxAccessDevices"" integer NOT NULL DEFAULT 0;
                    ALTER TABLE ""ServicePackages"" ADD COLUMN IF NOT EXISTS ""AllowWeb"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""ServicePackages"" ADD COLUMN IF NOT EXISTS ""AllowMobile"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""ServicePackages"" ADD COLUMN IF NOT EXISTS ""MaxBranches"" integer NOT NULL DEFAULT 0;
                    ALTER TABLE ""ServicePackages"" ADD COLUMN IF NOT EXISTS ""AllowFcm"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""ServicePackages"" ADD COLUMN IF NOT EXISTS ""AllowedFcmCategories"" text NOT NULL DEFAULT '[]';
                    ALTER TABLE ""ServicePackages"" ADD COLUMN IF NOT EXISTS ""IsPublic"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""Stores"" ADD COLUMN IF NOT EXISTS ""MaxAccessDevices"" integer NOT NULL DEFAULT 0;
                    ALTER TABLE ""Stores"" ADD COLUMN IF NOT EXISTS ""AllowWeb"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""Stores"" ADD COLUMN IF NOT EXISTS ""AllowMobile"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""Stores"" ADD COLUMN IF NOT EXISTS ""MaxBranches"" integer NOT NULL DEFAULT 0;
                    ALTER TABLE ""Stores"" ADD COLUMN IF NOT EXISTS ""AllowFcm"" boolean NOT NULL DEFAULT true;
                    ALTER TABLE ""Stores"" ADD COLUMN IF NOT EXISTS ""AllowedFcmCategories"" text NOT NULL DEFAULT '[]';

                    CREATE TABLE IF NOT EXISTS ""StoreAccessDevices"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""UserId"" uuid NULL,
                        ""DeviceKey"" character varying(80) NOT NULL,
                        ""Platform"" character varying(20) NOT NULL DEFAULT 'web',
                        ""DeviceName"" character varying(200) NULL,
                        ""LastSeenAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_StoreAccessDevices"" PRIMARY KEY (""Id"")
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_StoreAccessDevices_Store_DeviceKey""
                        ON ""StoreAccessDevices"" (""StoreId"", ""DeviceKey"");

                    CREATE TABLE IF NOT EXISTS ""ServerMetricSamples"" (
                        ""Id"" uuid NOT NULL,
                        ""SampledAt"" timestamp without time zone NOT NULL,
                        ""CpuPercent"" double precision NOT NULL,
                        ""RamPercent"" double precision NOT NULL,
                        ""RamUsedMb"" bigint NOT NULL DEFAULT 0,
                        ""RamTotalMb"" bigint NOT NULL DEFAULT 0,
                        ""ProcessWorkingSetMb"" bigint NOT NULL DEFAULT 0,
                        ""Source"" character varying(20) NOT NULL DEFAULT 'unknown',
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        CONSTRAINT ""PK_ServerMetricSamples"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_ServerMetricSamples_SampledAt""
                        ON ""ServerMetricSamples"" (""SampledAt"");

                    CREATE TABLE IF NOT EXISTS ""PosKitchenVoidSlips"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""SaleOrderId"" uuid NULL,
                        ""OrderNo"" character varying(40) NULL,
                        ""ResourceSessionId"" uuid NULL,
                        ""ServiceResourceId"" uuid NULL,
                        ""ResourceName"" character varying(120) NULL,
                        ""ProductId"" uuid NULL,
                        ""ProductName"" character varying(200) NOT NULL,
                        ""UnitName"" character varying(40) NULL,
                        ""Qty"" numeric(18,3) NOT NULL DEFAULT 0,
                        ""LineNote"" character varying(300) NULL,
                        ""AfterBillRequested"" boolean NOT NULL DEFAULT false,
                        ""Printed"" boolean NOT NULL DEFAULT false,
                        ""VoidedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""VoidedBy"" character varying(200) NULL,
                        ""DeviceName"" character varying(120) NULL,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosKitchenVoidSlips"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosKitchenVoidSlips_Store_VoidedAt""
                        ON ""PosKitchenVoidSlips"" (""StoreId"", ""VoidedAt"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosKitchenVoidSlips_Store_AfterBill""
                        ON ""PosKitchenVoidSlips"" (""StoreId"", ""AfterBillRequested"", ""VoidedAt"");
                    ALTER TABLE ""PosKitchenVoidSlips"" ADD COLUMN IF NOT EXISTS ""Reason"" character varying(80) NULL;
                    ALTER TABLE ""PosKitchenVoidSlips"" ADD COLUMN IF NOT EXISTS ""DetailNote"" character varying(500) NULL;
                    ALTER TABLE ""PosKitchenVoidSlips"" ADD COLUMN IF NOT EXISTS ""KdsAckedAt"" timestamp without time zone NULL;

                    CREATE TABLE IF NOT EXISTS ""PosCancelReturnAudits"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""ActionType"" character varying(40) NOT NULL,
                        ""Reason"" character varying(80) NULL,
                        ""DetailNote"" character varying(500) NULL,
                        ""AfterProvisionalBill"" boolean NOT NULL DEFAULT false,
                        ""SaleOrderId"" uuid NULL,
                        ""OrderNo"" character varying(40) NULL,
                        ""ResourceSessionId"" uuid NULL,
                        ""ServiceResourceId"" uuid NULL,
                        ""ResourceName"" character varying(120) NULL,
                        ""ProductId"" uuid NULL,
                        ""ProductName"" character varying(200) NULL,
                        ""UnitName"" character varying(40) NULL,
                        ""Qty"" numeric(18,3) NOT NULL DEFAULT 0,
                        ""Amount"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""OccurredAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""Actor"" character varying(200) NULL,
                        ""DeviceName"" character varying(120) NULL,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosCancelReturnAudits"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosCancelReturnAudits_Store_Occurred""
                        ON ""PosCancelReturnAudits"" (""StoreId"", ""OccurredAt"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosCancelReturnAudits_Store_Action""
                        ON ""PosCancelReturnAudits"" (""StoreId"", ""ActionType"", ""OccurredAt"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosCancelReturnAudits_Store_AfterProv""
                        ON ""PosCancelReturnAudits"" (""StoreId"", ""AfterProvisionalBill"", ""OccurredAt"");

                    CREATE TABLE IF NOT EXISTS ""PosPaymentGatewaySettings"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""DefaultTransferProvider"" integer NOT NULL DEFAULT 0,
                        ""TingeeEnabled"" boolean NOT NULL DEFAULT false,
                        ""TingeeClientId"" character varying(100) NULL,
                        ""TingeeSecretKey"" character varying(300) NULL,
                        ""TingeeVaAccountNumber"" character varying(100) NULL,
                        ""TingeeMerchantId"" character varying(50) NULL,
                        ""TingeeWebhookSecret"" character varying(300) NULL,
                        ""ExtraJson"" character varying(4000) NULL,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosPaymentGatewaySettings"" PRIMARY KEY (""Id"")
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosPaymentGatewaySettings_StoreId""
                        ON ""PosPaymentGatewaySettings"" (""StoreId"");

                    CREATE TABLE IF NOT EXISTS ""PosStoreNotificationCredits"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""RemainingCount"" integer NOT NULL DEFAULT 0,
                        ""TotalGranted"" integer NOT NULL DEFAULT 0,
                        ""TotalConsumed"" integer NOT NULL DEFAULT 0,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosStoreNotificationCredits"" PRIMARY KEY (""Id"")
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosStoreNotificationCredits_StoreId""
                        ON ""PosStoreNotificationCredits"" (""StoreId"");

                    CREATE TABLE IF NOT EXISTS ""PosNotificationCreditPackages"" (
                        ""Id"" uuid NOT NULL,
                        ""Name"" character varying(120) NOT NULL,
                        ""CreditCount"" integer NOT NULL DEFAULT 0,
                        ""Price"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""IsPublic"" boolean NOT NULL DEFAULT true,
                        ""Description"" character varying(500) NULL,
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosNotificationCreditPackages"" PRIMARY KEY (""Id"")
                    );

                    CREATE TABLE IF NOT EXISTS ""PosNotificationCreditPurchases"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""PackageId"" uuid NULL,
                        ""CreditCount"" integer NOT NULL DEFAULT 0,
                        ""AmountPaid"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""Status"" integer NOT NULL DEFAULT 0,
                        ""ExternalPaymentRef"" character varying(120) NULL,
                        ""PaidAt"" timestamp without time zone NULL,
                        ""Note"" character varying(500) NULL,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosNotificationCreditPurchases"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosNotificationCreditPurchases_Store_Status""
                        ON ""PosNotificationCreditPurchases"" (""StoreId"", ""Status"");

                    CREATE TABLE IF NOT EXISTS ""PosNotificationCreditLedgers"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""Delta"" integer NOT NULL DEFAULT 0,
                        ""BalanceAfter"" integer NOT NULL DEFAULT 0,
                        ""Source"" integer NOT NULL DEFAULT 0,
                        ""ReferenceId"" uuid NULL,
                        ""ProviderTransactionCode"" character varying(120) NULL,
                        ""Provider"" integer NULL,
                        ""Note"" character varying(500) NULL,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosNotificationCreditLedgers"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosNotificationCreditLedgers_Store_Created""
                        ON ""PosNotificationCreditLedgers"" (""StoreId"", ""CreatedAt"");
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosNotificationCreditLedgers_ProviderTxn""
                        ON ""PosNotificationCreditLedgers"" (""ProviderTransactionCode"")
                        WHERE ""ProviderTransactionCode"" IS NOT NULL AND ""Deleted"" IS NULL;

                    CREATE TABLE IF NOT EXISTS ""PosTransferPaymentIntents"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NOT NULL,
                        ""SaleOrderId"" uuid NULL,
                        ""ExternalOrderId"" character varying(100) NOT NULL,
                        ""OrderNo"" character varying(40) NULL,
                        ""AmountExpected"" numeric(18,2) NOT NULL DEFAULT 0,
                        ""Provider"" integer NOT NULL DEFAULT 1,
                        ""Status"" integer NOT NULL DEFAULT 0,
                        ""ProviderTransactionCode"" character varying(120) NULL,
                        ""TransferContent"" character varying(500) NULL,
                        ""ConfirmedAt"" timestamp without time zone NULL,
                        ""CompletedAt"" timestamp without time zone NULL,
                        ""ExpiresAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""TableName"" character varying(200) NULL,
                        ""RawWebhookJson"" character varying(2000) NULL,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosTransferPaymentIntents"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosTransferPaymentIntents_Store_Status""
                        ON ""PosTransferPaymentIntents"" (""StoreId"", ""Status"", ""CreatedAt"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosTransferPaymentIntents_Store_ExternalOrder""
                        ON ""PosTransferPaymentIntents"" (""StoreId"", ""ExternalOrderId"");

                    CREATE TABLE IF NOT EXISTS ""PosPaymentWebhookEvents"" (
                        ""Id"" uuid NOT NULL,
                        ""StoreId"" uuid NULL,
                        ""Provider"" integer NOT NULL DEFAULT 1,
                        ""ProviderTransactionCode"" character varying(120) NULL,
                        ""EventType"" character varying(80) NULL,
                        ""SignatureValid"" boolean NOT NULL DEFAULT false,
                        ""ResultCode"" character varying(10) NULL,
                        ""TransferIntentId"" uuid NULL,
                        ""PayloadJson"" character varying(8000) NULL,
                        ""ReceivedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""UpdatedBy"" text NULL,
                        ""CreatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL,
                        CONSTRAINT ""PK_PosPaymentWebhookEvents"" PRIMARY KEY (""Id"")
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosPaymentWebhookEvents_Provider_Txn""
                        ON ""PosPaymentWebhookEvents"" (""Provider"", ""ProviderTransactionCode"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosPaymentWebhookEvents_ReceivedAt""
                        ON ""PosPaymentWebhookEvents"" (""ReceivedAt"");

                    -- Không còn dùng «cần dọn» — bàn trống ngay sau thanh toán.
                    UPDATE ""PosServiceResources"" SET ""NeedsCleaning"" = false WHERE ""NeedsCleaning"" = true;

                    CREATE TABLE IF NOT EXISTS ""PosProductToppingOptions"" (
                        ""Id"" uuid PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ProductId"" uuid NOT NULL,
                        ""ToppingProductId"" uuid NOT NULL,
                        ""ExtraPrice"" numeric(18,2) NULL,
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""CreatedBy"" text NULL,
                        ""UpdatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosProductToppingOptions_Store_Product""
                        ON ""PosProductToppingOptions"" (""StoreId"", ""ProductId"");

                    CREATE TABLE IF NOT EXISTS ""PosToppingGroups"" (
                        ""Id"" uuid PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""Name"" character varying(200) NOT NULL,
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""CreatedBy"" text NULL,
                        ""UpdatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosToppingGroups_Store""
                        ON ""PosToppingGroups"" (""StoreId"");

                    CREATE TABLE IF NOT EXISTS ""PosToppingGroupItems"" (
                        ""Id"" uuid PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""GroupId"" uuid NOT NULL,
                        ""ToppingProductId"" uuid NOT NULL,
                        ""ExtraPrice"" numeric(18,2) NULL,
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""CreatedBy"" text NULL,
                        ""UpdatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosToppingGroupItems_Store_Group""
                        ON ""PosToppingGroupItems"" (""StoreId"", ""GroupId"");

                    CREATE TABLE IF NOT EXISTS ""PosProductToppingGroupLinks"" (
                        ""Id"" uuid PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ProductId"" uuid NOT NULL,
                        ""GroupId"" uuid NOT NULL,
                        ""SortOrder"" integer NOT NULL DEFAULT 0,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""CreatedBy"" text NULL,
                        ""UpdatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL
                    );
                    CREATE UNIQUE INDEX IF NOT EXISTS ""IX_PosProductToppingGroupLinks_Store_Product_Group""
                        ON ""PosProductToppingGroupLinks"" (""StoreId"", ""ProductId"", ""GroupId"");

                    CREATE TABLE IF NOT EXISTS ""PosResourceReservations"" (
                        ""Id"" uuid PRIMARY KEY,
                        ""StoreId"" uuid NOT NULL,
                        ""ResourceId"" uuid NOT NULL,
                        ""CustomerId"" uuid NULL,
                        ""CustomerName"" character varying(200) NOT NULL DEFAULT '',
                        ""Phone"" character varying(30) NULL,
                        ""GuestCount"" integer NOT NULL DEFAULT 1,
                        ""ReservedAt"" timestamp without time zone NOT NULL,
                        ""ReservedUntil"" timestamp without time zone NULL,
                        ""Status"" integer NOT NULL DEFAULT 0,
                        ""PreOrderJson"" text NULL,
                        ""Note"" character varying(500) NULL,
                        ""SeatedSessionId"" uuid NULL,
                        ""IsActive"" boolean NOT NULL DEFAULT true,
                        ""CreatedAt"" timestamp without time zone NOT NULL DEFAULT NOW(),
                        ""UpdatedAt"" timestamp without time zone NULL,
                        ""CreatedBy"" text NULL,
                        ""UpdatedBy"" text NULL,
                        ""LastModified"" timestamp without time zone NULL,
                        ""LastModifiedBy"" text NULL,
                        ""Deleted"" timestamp without time zone NULL,
                        ""DeletedBy"" text NULL
                    );
                    CREATE INDEX IF NOT EXISTS ""IX_PosResourceReservations_Store_Resource_Status""
                        ON ""PosResourceReservations"" (""StoreId"", ""ResourceId"", ""Status"");
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""DepositAmount"" numeric(18,2) NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""DepositPaid"" numeric(18,2) NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""DepositStatus"" integer NOT NULL DEFAULT 0;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""DepositPaymentMethod"" character varying(50) NULL;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""DepositPaidAt"" timestamp without time zone NULL;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""DepositAppliedOrderId"" uuid NULL;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""DurationMinutes"" integer NULL;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""ServiceProductId"" uuid NULL;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""AssignedEmployeeId"" uuid NULL;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""Occasion"" character varying(40) NULL;
                    ALTER TABLE ""PosResourceReservations"" ADD COLUMN IF NOT EXISTS ""SpecialRequest"" character varying(500) NULL;
                    CREATE INDEX IF NOT EXISTS ""IX_PosResourceReservations_Store_Status_Until""
                        ON ""PosResourceReservations"" (""StoreId"", ""Status"", ""ReservedUntil"");
                    CREATE INDEX IF NOT EXISTS ""IX_PosResourceReservations_Store_Employee_Slot""
                        ON ""PosResourceReservations"" (""StoreId"", ""AssignedEmployeeId"", ""Status"", ""ReservedAt"");

                    ALTER TABLE ""PosProducts"" ADD COLUMN IF NOT EXISTS ""SortOrder"" integer NOT NULL DEFAULT 0;
                    CREATE INDEX IF NOT EXISTS ""IX_PosProducts_Store_SortOrder""
                        ON ""PosProducts"" (""StoreId"", ""SortOrder"");
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
                    ('a0000001-0000-0000-0000-000000000011', 'internal_comm', 'Truyền thông nội bộ', 'Thông báo nội bộ, tin tức công ty', 'campaign', 11, TRUE, TRUE, NOW()),
                    ('a0000001-0000-0000-0000-000000000012', 'pos', 'Bán hàng POS', 'Tồn kho thấp, đơn bán, nhập hàng', 'point_of_sale', 12, TRUE, TRUE, NOW())
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
            await SyncEmployeeRolePermissionsAsync();
            await PatchPosSellOpsRolePermissionsAsync();
            await PatchPosReportRolePermissionsAsync();
            await SeedServicePackagesAsync();
            await PatchPosReportPackageModulesAsync();
            await SeedPosProductSampleCatalogAsync();

            await context.SaveChangesAsync();
            logger.LogInformation("Database seeding completed successfully.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "An error occurred while seeding the database.");
        }
    }

    private async Task SeedPosProductSampleCatalogAsync()
    {
        if (await context.PosProductSampleCatalog.AnyAsync(x => x.Deleted == null))
            return;

        foreach (var row in PosSampleCatalogDefaults.All())
            context.PosProductSampleCatalog.Add(PosSampleCatalogDefaults.ToEntity(row, "System"));

        logger.LogInformation("Seeded default PosProductSampleCatalog rows.");
    }

    #region Seed Roles
    
    private async Task SeedRolesAsync()
    {
        var roles = new[] { nameof(Roles.SuperAdmin), nameof(Roles.Admin), nameof(Roles.Director), nameof(Roles.User), nameof(Roles.Manager), nameof(Roles.Employee), nameof(Roles.Agent), nameof(Roles.DepartmentHead), nameof(Roles.Accountant), nameof(Roles.Cashier), nameof(Roles.Waiter) };

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

    #region Seed Service Packages

    private async Task SeedServicePackagesAsync()
    {
        const string basicName = PosPackageDefaults.BasicPackageName;
        var basicJson = System.Text.Json.JsonSerializer.Serialize(PosPackageDefaults.BasicModules);

        var existing = await context.ServicePackages
            .FirstOrDefaultAsync(p => p.Name == basicName);
        if (existing == null)
        {
            context.ServicePackages.Add(new ServicePackage
            {
                Id = Guid.Parse("b0000001-0000-0000-0000-000000000001"),
                Name = basicName,
                Description = "Bán hàng POS cơ bản: hàng hóa, bán hàng, đơn hàng, trả hàng, mẫu in",
                IsActive = true,
                DefaultDurationDays = 30,
                MaxUsers = 20,
                MaxDevices = 2,
                AllowedModules = basicJson,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = "System",
            });
            logger.LogInformation("Seeded service package: {Name}", basicName);
        }
        else
        {
            var mods = StorePackageHelper.DeserializeModules(existing.AllowedModules);
            if (mods.Count == 0)
            {
                existing.AllowedModules = basicJson;
                existing.UpdatedAt = DateTime.UtcNow;
                existing.UpdatedBy = "System";
                logger.LogInformation("Updated empty modules for package: {Name}", basicName);
            }
            else if (mods.Contains("PosSell", StringComparer.OrdinalIgnoreCase))
            {
                var added = false;
                if (!mods.Contains("PosSaleReturns", StringComparer.OrdinalIgnoreCase))
                {
                    mods.Add("PosSaleReturns");
                    added = true;
                }
                foreach (var addon in PosPackageDefaults.SellAddonModules)
                {
                    if (mods.Contains(addon, StringComparer.OrdinalIgnoreCase)) continue;
                    mods.Add(addon);
                    added = true;
                }
                if (added)
                {
                    existing.AllowedModules = System.Text.Json.JsonSerializer.Serialize(mods);
                    existing.Description =
                        "Bán hàng POS cơ bản: hàng hóa, bán hàng, đơn hàng, trả hàng, CRM, đặt bàn, BH, màn phụ";
                    existing.UpdatedAt = DateTime.UtcNow;
                    existing.UpdatedBy = "System";
                    logger.LogInformation("Patched POS addon modules on package: {Name}", basicName);
                }
            }
        }

        // Mọi gói đang có PosSell → bổ sung 4 addon tách riêng (không gãy cửa hàng cũ).
        await PatchPosSellAddonModulesAsync();
    }

    private async Task PatchPosSellAddonModulesAsync()
    {
        var packages = await context.ServicePackages
            .Where(p => p.IsActive)
            .ToListAsync();
        foreach (var pkg in packages)
        {
            var mods = StorePackageHelper.DeserializeModules(pkg.AllowedModules);
            if (!mods.Contains("PosSell", StringComparer.OrdinalIgnoreCase)) continue;
            var changed = false;
            foreach (var addon in PosPackageDefaults.SellAddonModules)
            {
                if (mods.Contains(addon, StringComparer.OrdinalIgnoreCase)) continue;
                mods.Add(addon);
                changed = true;
            }
            if (!changed) continue;
            pkg.AllowedModules = System.Text.Json.JsonSerializer.Serialize(mods);
            pkg.UpdatedAt = DateTime.UtcNow;
            pkg.UpdatedBy = "System";
            logger.LogInformation("Added POS sell addons to package: {Name}", pkg.Name);
        }
    }

    #endregion

    #region Seed Permission Modules

    /// <summary>GUID cố định khớp Flutter permission_module_catalog + PermissionConfiguration.</summary>
    private static readonly Dictionary<string, Guid> StablePermissionIds = new(StringComparer.OrdinalIgnoreCase)
    {
        ["PosProducts"] = Guid.Parse("11111111-1111-1111-1111-111111111083"),
        ["PosSell"] = Guid.Parse("11111111-1111-1111-1111-111111111087"),
        ["PosSalesReport"] = Guid.Parse("11111111-1111-1111-1111-111111111084"),
        ["PosReportRevenue"] = Guid.Parse("11111111-1111-1111-1111-111111111108"),
        ["PosReportSoldGoods"] = Guid.Parse("11111111-1111-1111-1111-111111111109"),
        ["PosReportStock"] = Guid.Parse("11111111-1111-1111-1111-111111111110"),
        ["PosReportPurchases"] = Guid.Parse("11111111-1111-1111-1111-111111111111"),
        ["PosReportPayment"] = Guid.Parse("11111111-1111-1111-1111-111111111112"),
        ["PosReportDebt"] = Guid.Parse("11111111-1111-1111-1111-111111111113"),
        ["PosReportExpiry"] = Guid.Parse("11111111-1111-1111-1111-111111111114"),
        ["PosReportProfit"] = Guid.Parse("11111111-1111-1111-1111-111111111115"),
        ["PosReportExpense"] = Guid.Parse("11111111-1111-1111-1111-111111111116"),
        ["PosReportEndOfDay"] = Guid.Parse("11111111-1111-1111-1111-111111111117"),
        ["PosReportStaffRevenue"] = Guid.Parse("11111111-1111-1111-1111-111111111118"),
        ["PosReportCashbook"] = Guid.Parse("11111111-1111-1111-1111-111111111119"),
        ["PosReportPnl"] = Guid.Parse("11111111-1111-1111-1111-111111111120"),
        ["PosReportVoucher"] = Guid.Parse("11111111-1111-1111-1111-111111111121"),
        ["HkdBooks"] = Guid.Parse("11111111-1111-1111-1111-111111111102"),
        ["PosPrintTemplates"] = Guid.Parse("11111111-1111-1111-1111-111111111088"),
        ["PosSaleOrders"] = Guid.Parse("11111111-1111-1111-1111-111111111089"),
        ["PosSaleReturns"] = Guid.Parse("11111111-1111-1111-1111-111111111090"),
        ["PosPurchaseReceipts"] = Guid.Parse("11111111-1111-1111-1111-111111111091"),
        ["PosPurchaseReturns"] = Guid.Parse("11111111-1111-1111-1111-111111111092"),
        ["PosStockCounts"] = Guid.Parse("11111111-1111-1111-1111-111111111093"),
        ["PosDamageIssues"] = Guid.Parse("11111111-1111-1111-1111-111111111094"),
        ["PosInternalUseIssues"] = Guid.Parse("11111111-1111-1111-1111-111111111095"),
        ["PosBooking"] = Guid.Parse("11111111-1111-1111-1111-111111111097"),
        ["PosCustomers"] = Guid.Parse("11111111-1111-1111-1111-111111111098"),
        ["PosWarranty"] = Guid.Parse("11111111-1111-1111-1111-111111111099"),
        ["PosCustomerDisplay"] = Guid.Parse("11111111-1111-1111-1111-111111111100"),
        ["PosEInvoice"] = Guid.Parse("11111111-1111-1111-1111-111111111107"),
        ["PosKds"] = Guid.Parse("11111111-1111-1111-1111-111111111103"),
        ["PosQrOrder"] = Guid.Parse("11111111-1111-1111-1111-111111111104"),
        ["PosCashierShift"] = Guid.Parse("11111111-1111-1111-1111-111111111105"),
        ["PosPrinters"] = Guid.Parse("11111111-1111-1111-1111-111111111106"),
    };

    private async Task SeedPermissionModulesAsync()
    {
        var requiredModules = FeatureModuleCatalog.All
            .Select(m => (m.Code, m.DisplayName, m.Description, m.Order))
            .ToArray();

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
                // Stable Ids khớp Flutter permission_module_catalog (tránh lệch GUID khi gán role).
                var id = StablePermissionIds.TryGetValue(module, out var fixedId)
                    ? fixedId
                    : Guid.NewGuid();
                context.Permissions.Add(new Permission
                {
                    Id = id,
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
        var validModules = requiredModules.Select(m => m.Code).ToHashSet();
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
    }

    /// <summary>
    /// Role đã có PosSell nhưng chưa có dòng KDS/QR/ca/máy in/HĐĐT → chèn (không ghi đè chỉnh tay).
    /// </summary>
    private async Task PatchPosSellOpsRolePermissionsAsync()
    {
        var opsCodes = PosPackageDefaults.SellAddonModules
            .Concat(["PosKds", "PosQrOrder", "PosCashierShift", "PosPrinters", "PosEInvoice"])
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var perms = await context.Permissions
            .Where(p => p.Module == "PosSell" || opsCodes.Contains(p.Module))
            .ToListAsync();
        var sell = perms.FirstOrDefault(p => p.Module == "PosSell");
        if (sell == null) return;
        var ops = perms.Where(p => p.Module != "PosSell").ToList();
        if (ops.Count == 0) return;

        var sellRows = await context.RolePermissions
            .Where(rp => rp.PermissionId == sell.Id && rp.IsActive)
            .ToListAsync();
        if (sellRows.Count == 0) return;

        var opIds = ops.Select(o => o.Id).ToList();
        var existing = await context.RolePermissions
            .Where(rp => opIds.Contains(rp.PermissionId))
            .Select(rp => new { rp.RoleName, rp.StoreId, rp.PermissionId })
            .ToListAsync();
        var have = existing
            .Select(x => (x.RoleName, Store: x.StoreId, x.PermissionId))
            .ToHashSet();

        var inserted = 0;
        foreach (var src in sellRows)
        {
            foreach (var op in ops)
            {
                if (have.Contains((src.RoleName, src.StoreId, op.Id))) continue;
                var (v, c, e, d, x, a) = ModulePermissionDefaults.Get(src.RoleName, op.Module);
                if (!v && !c && !e && !d && !x && !a)
                {
                    v = src.CanView;
                    c = src.CanCreate && op.Module is "PosKds" or "PosCashierShift";
                    e = (src.CanEdit || src.CanCreate) && op.Module is "PosQrOrder" or "PosPrinters";
                    a = src.CanApprove && op.Module == "PosEInvoice";
                    if (op.Module == "PosEInvoice") v = src.CanView;
                    if (op.Module is "PosPrinters" or "PosQrOrder" or "PosKds") v = src.CanView;
                }
                if (!v && !c && !e && !d && !x && !a) continue;
                context.RolePermissions.Add(new RolePermission
                {
                    Id = Guid.NewGuid(),
                    RoleName = src.RoleName,
                    RoleDisplayName = src.RoleDisplayName,
                    PermissionId = op.Id,
                    StoreId = src.StoreId,
                    CanView = v,
                    CanCreate = c,
                    CanEdit = e,
                    CanDelete = d,
                    CanExport = x,
                    CanApprove = a,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow,
                    CreatedBy = "System",
                });
                inserted++;
            }
        }
        if (inserted > 0)
            logger.LogInformation("Patched {Count} POS ops RolePermissions from PosSell", inserted);
    }

    /// <summary>
    /// Role đã có PosSalesReport hoặc PosProducts (xem/xuất) → chèn 14 báo cáo tách (không ghi đè).
    /// </summary>
    private async Task PatchPosReportRolePermissionsAsync()
    {
        var reportCodes = PosPackageDefaults.ReportModules;
        var perms = await context.Permissions
            .Where(p => p.Module == "PosSalesReport" || p.Module == "PosProducts" || reportCodes.Contains(p.Module))
            .ToListAsync();
        var srcPerms = perms.Where(p => p.Module is "PosSalesReport" or "PosProducts").ToList();
        var reports = perms.Where(p => reportCodes.Contains(p.Module, StringComparer.OrdinalIgnoreCase)).ToList();
        if (srcPerms.Count == 0 || reports.Count == 0) return;

        var srcIds = srcPerms.Select(p => p.Id).ToList();
        var srcRows = await context.RolePermissions
            .Where(rp => srcIds.Contains(rp.PermissionId) && rp.IsActive && (rp.CanView || rp.CanExport))
            .ToListAsync();
        if (srcRows.Count == 0) return;

        var reportIds = reports.Select(r => r.Id).ToList();
        var existing = await context.RolePermissions
            .Where(rp => reportIds.Contains(rp.PermissionId))
            .Select(rp => new { rp.RoleName, rp.StoreId, rp.PermissionId })
            .ToListAsync();
        var have = existing
            .Select(x => (x.RoleName, Store: x.StoreId, x.PermissionId))
            .ToHashSet();

        var inserted = 0;
        foreach (var grp in srcRows.GroupBy(r => (r.RoleName, r.StoreId)))
        {
            var view = grp.Any(r => r.CanView);
            var export = grp.Any(r => r.CanExport);
            if (!view && !export) continue;
            var sample = grp.First();
            foreach (var report in reports)
            {
                if (have.Contains((sample.RoleName, sample.StoreId, report.Id))) continue;
                var (v, c, e, d, x, a) = ModulePermissionDefaults.Get(sample.RoleName, report.Module);
                if (!v && !x)
                {
                    v = view;
                    x = export;
                }
                if (!v && !x) continue;
                context.RolePermissions.Add(new RolePermission
                {
                    Id = Guid.NewGuid(),
                    RoleName = sample.RoleName,
                    RoleDisplayName = sample.RoleDisplayName,
                    PermissionId = report.Id,
                    StoreId = sample.StoreId,
                    CanView = v,
                    CanCreate = c,
                    CanEdit = e,
                    CanDelete = d,
                    CanExport = x,
                    CanApprove = a,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow,
                    CreatedBy = "System",
                });
                inserted++;
            }
        }
        if (inserted > 0)
            logger.LogInformation("Patched {Count} POS report RolePermissions from PosSalesReport/PosProducts", inserted);
    }

    /// <summary>Gói đang có PosSalesReport (hoặc kho PosProducts) → bổ sung 14 báo cáo tách.</summary>
    private async Task PatchPosReportPackageModulesAsync()
    {
        var packages = await context.ServicePackages
            .Where(p => p.IsActive)
            .ToListAsync();
        foreach (var pkg in packages)
        {
            var mods = StorePackageHelper.DeserializeModules(pkg.AllowedModules);
            var hasHub = mods.Contains("PosSalesReport", StringComparer.OrdinalIgnoreCase);
            var hasWh = mods.Contains("PosProducts", StringComparer.OrdinalIgnoreCase);
            if (!hasHub && !hasWh) continue;
            var add = hasHub
                ? PosPackageDefaults.ReportModules
                : new[] { "PosReportSoldGoods", "PosReportStock", "PosReportExpiry", "PosReportEndOfDay" };
            var changed = false;
            foreach (var code in add)
            {
                if (mods.Contains(code, StringComparer.OrdinalIgnoreCase)) continue;
                mods.Add(code);
                changed = true;
            }
            if (!changed) continue;
            pkg.AllowedModules = System.Text.Json.JsonSerializer.Serialize(mods);
            pkg.UpdatedAt = DateTime.UtcNow;
            pkg.UpdatedBy = "System";
            logger.LogInformation("Added POS report modules to package: {Name}", pkg.Name);
        }
    }

    /// <summary>
    /// Đồng bộ RolePermissions cho role Employee theo ModulePermissionDefaults (mọi store).
    /// Ghi đè quyền cũ — seed-if-empty không cập nhật cửa hàng đã có dữ liệu.
    /// </summary>
    private async Task SyncEmployeeRolePermissionsAsync()
    {
        const string roleName = nameof(Roles.Employee);
        var modules = await context.Permissions.AsNoTracking().ToListAsync();
        if (modules.Count == 0) return;

        var storeIds = await context.Stores.AsNoTracking().Select(s => s.Id).ToListAsync();
        var scopes = storeIds.Select(id => (Guid?)id).ToList();
        if (await context.RolePermissions.AnyAsync(rp => rp.RoleName == roleName && rp.StoreId == null))
            scopes.Add(null);

        var updated = 0;
        var inserted = 0;
        var now = DateTime.UtcNow;

        foreach (var storeId in scopes)
        {
            var existing = await context.RolePermissions
                .Where(rp => rp.RoleName == roleName && rp.StoreId == storeId)
                .ToListAsync();
            var byPermissionId = existing.ToDictionary(rp => rp.PermissionId);

            foreach (var module in modules)
            {
                var (canView, canCreate, canEdit, canDelete, canExport, canApprove) =
                    ModulePermissionDefaults.Get(roleName, module.Module);
                if (byPermissionId.TryGetValue(module.Id, out var row))
                {
                    if (row.CanView == canView
                        && row.CanCreate == canCreate
                        && row.CanEdit == canEdit
                        && row.CanDelete == canDelete
                        && row.CanExport == canExport
                        && row.CanApprove == canApprove)
                    {
                        continue;
                    }

                    row.CanView = canView;
                    row.CanCreate = canCreate;
                    row.CanEdit = canEdit;
                    row.CanDelete = canDelete;
                    row.CanExport = canExport;
                    row.CanApprove = canApprove;
                    row.UpdatedAt = now;
                    row.UpdatedBy = "System";
                    updated++;
                }
                else
                {
                    context.RolePermissions.Add(new RolePermission
                    {
                        Id = Guid.NewGuid(),
                        StoreId = storeId,
                        RoleName = roleName,
                        RoleDisplayName = "Nhân viên",
                        PermissionId = module.Id,
                        CanView = canView,
                        CanCreate = canCreate,
                        CanEdit = canEdit,
                        CanDelete = canDelete,
                        CanExport = canExport,
                        CanApprove = canApprove,
                        CreatedAt = now,
                        CreatedBy = "System"
                    });
                    inserted++;
                }
            }
        }

        if (updated > 0 || inserted > 0)
        {
            await context.SaveChangesAsync();
            logger.LogInformation(
                "Employee RolePermissions synced: {Updated} updated, {Inserted} inserted across {StoreCount} stores.",
                updated, inserted, storeIds.Count);
        }
        else
        {
            logger.LogInformation("Employee RolePermissions already match defaults.");
        }
    }

    #endregion

}
