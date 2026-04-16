using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddPenaltyTickets : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Use IF EXISTS to avoid failures on fresh databases where these constraints/indexes/columns may not exist
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP CONSTRAINT IF EXISTS ""FK_AttendanceCorrectionRequests_AspNetUsers_ApprovedById"";");
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP CONSTRAINT IF EXISTS ""FK_AttendanceCorrectionRequests_AspNetUsers_CreatedByUserId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP CONSTRAINT IF EXISTS ""FK_AttendanceCorrectionRequests_AspNetUsers_EmployeeUserId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP CONSTRAINT IF EXISTS ""FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""Employees"" DROP CONSTRAINT IF EXISTS ""FK_Employees_Branches_BranchId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""Leaves"" DROP CONSTRAINT IF EXISTS ""FK_Leaves_Employees_ReplacementEmployeeId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""PaymentTransactions"" DROP CONSTRAINT IF EXISTS ""FK_PaymentTransactions_AspNetUsers_EmployeeUserId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""PaymentTransactions"" DROP CONSTRAINT IF EXISTS ""FK_PaymentTransactions_Employees_EmployeeId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""Shifts"" DROP CONSTRAINT IF EXISTS ""FK_Shifts_AttendanceLogs_CheckInAttendanceId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""Shifts"" DROP CONSTRAINT IF EXISTS ""FK_Shifts_AttendanceLogs_CheckOutAttendanceId"";");

            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_WorkSchedules_Employee_Date_Shift"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Store_ExpiryDate"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Store_IsActive"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Store_IsActive_IsLocked"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Store_IsLocked"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Leaves_StoreId"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_KpiEmployeeTargets_EmployeeId"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Device_DeviceStatus"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Device_IsClaimed"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Device_LastOnline"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Device_StoreId_DeviceStatus"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Attendance_AttendanceTime"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Attendance_DeviceId_AttendanceTime"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Attendance_EmployeeId_AttendanceTime"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_AttendanceCorrectionRequests_CreatedByUserId"";");

            migrationBuilder.Sql(@"ALTER TABLE ""ShiftTemplates"" DROP COLUMN IF EXISTS ""EarlyCheckInMinutes"";");
            migrationBuilder.Sql(@"ALTER TABLE ""ShiftTemplates"" DROP COLUMN IF EXISTS ""EarlyLeaveGraceMinutes"";");
            migrationBuilder.Sql(@"ALTER TABLE ""ShiftTemplates"" DROP COLUMN IF EXISTS ""LateGraceMinutes"";");
            migrationBuilder.Sql(@"ALTER TABLE ""ShiftTemplates"" DROP COLUMN IF EXISTS ""OvertimeMinutesThreshold"";");
            migrationBuilder.Sql(@"ALTER TABLE ""InsuranceSettings"" DROP COLUMN IF EXISTS ""MaxBhtnRegionI"";");
            migrationBuilder.Sql(@"ALTER TABLE ""InsuranceSettings"" DROP COLUMN IF EXISTS ""MaxBhtnRegionII"";");
            migrationBuilder.Sql(@"ALTER TABLE ""InsuranceSettings"" DROP COLUMN IF EXISTS ""MaxBhtnRegionIII"";");
            migrationBuilder.Sql(@"ALTER TABLE ""InsuranceSettings"" DROP COLUMN IF EXISTS ""MaxBhtnRegionIV"";");
            migrationBuilder.Sql(@"ALTER TABLE ""DeviceUsers"" DROP COLUMN IF EXISTS ""DisplayName"";");
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP COLUMN IF EXISTS ""CreatedAttendanceId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP COLUMN IF EXISTS ""CreatedByUserId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP COLUMN IF EXISTS ""OriginalAttendanceState"";");
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP COLUMN IF EXISTS ""StoredEmployeeCode"";");
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP COLUMN IF EXISTS ""StoredEmployeeName"";");
            migrationBuilder.Sql(@"ALTER TABLE ""AttendanceCorrectionRequests"" DROP COLUMN IF EXISTS ""StoredPin"";");
            migrationBuilder.Sql(@"ALTER TABLE ""Allowances"" DROP COLUMN IF EXISTS ""DailyCalcMethod"";");
            migrationBuilder.Sql(@"ALTER TABLE ""Allowances"" DROP COLUMN IF EXISTS ""StandardWorkDays"";");

            // Conditional renames - use DO blocks to handle missing indexes/columns on fresh DB
            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_WorkSchedules_EmployeeId"" RENAME TO ""IX_WorkSchedules_EmployeeUserId""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");
            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_Store_Code"" RENAME TO ""IX_Stores_Code""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");
            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_Store_AgentId"" RENAME TO ""IX_Stores_AgentId""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");

            migrationBuilder.Sql(@"DO $$ BEGIN ALTER TABLE ""ShiftTemplates"" RENAME COLUMN ""AssignedEmployeeIds"" TO ""Description""; EXCEPTION WHEN undefined_column THEN NULL; END $$;");

            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_ScheduleRegistrations_EmployeeId"" RENAME TO ""IX_ScheduleRegistrations_EmployeeUserId""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");

            migrationBuilder.Sql(@"DO $$ BEGIN ALTER TABLE ""SalaryProfiles"" RENAME COLUMN ""CustomWorkDays"" TO ""SocialInsuranceType""; EXCEPTION WHEN undefined_column THEN NULL; END $$;");

            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_KpiEmployeeTargets_KpiPeriodId"" RENAME TO ""IX_KpiEmployeeTarget_PeriodId""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");

            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_Device_StoreId"" RENAME TO ""IX_Devices_StoreId""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");
            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_Device_SerialNumber"" RENAME TO ""IX_Devices_SerialNumber""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");

            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_Attendance_PIN"" RENAME TO ""IX_AttendanceLogs_PIN""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");
            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_Attendance_EmployeeId"" RENAME TO ""IX_AttendanceLogs_EmployeeId""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");
            migrationBuilder.Sql(@"DO $$ BEGIN ALTER INDEX ""IX_Attendance_DeviceId"" RENAME TO ""IX_AttendanceLogs_DeviceId""; EXCEPTION WHEN undefined_object THEN NULL; END $$;");

            migrationBuilder.Sql(@"DO $$ BEGIN ALTER TABLE ""AttendanceCorrectionRequests"" RENAME COLUMN ""NewType"" TO ""EmployeeCode""; EXCEPTION WHEN undefined_column THEN NULL; END $$;");

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "TransactionCategories",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "SystemConfigurations",
                type: "uuid",
                nullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "LockReason",
                table: "Stores",
                type: "text",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "character varying(500)",
                oldMaxLength: 500,
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "LicenseKey",
                table: "Stores",
                type: "text",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "character varying(100)",
                oldMaxLength: 100,
                oldNullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AttendanceMode",
                table: "SalaryProfiles",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "CompletionSalary",
                table: "SalaryProfiles",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "DailyFixedRate",
                table: "SalaryProfiles",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "FixedShiftRate",
                table: "SalaryProfiles",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "HolidayOvertimeDailyRate",
                table: "SalaryProfiles",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "HolidayOvertimeType",
                table: "SalaryProfiles",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "HourlyOvertimeFixedRate",
                table: "SalaryProfiles",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "HourlyOvertimeType",
                table: "SalaryProfiles",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "InsuranceSalary",
                table: "SalaryProfiles",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PaidLeaveType",
                table: "SalaryProfiles",
                type: "character varying(30)",
                maxLength: 30,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ShiftSalaryType",
                table: "SalaryProfiles",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ShiftsPerDay",
                table: "SalaryProfiles",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CategoryCode",
                table: "Notifications",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "EmployeeId",
                table: "Leaves",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "ShiftId",
                table: "Leaves",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"));

            migrationBuilder.AddColumn<bool>(
                name: "AutoSyncEnabled",
                table: "KpiPeriods",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "AutoSyncTimeSlots",
                table: "KpiPeriods",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "AutoSyncEnabled",
                table: "KpiEmployeeTargets",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "GoogleCellPosition",
                table: "KpiEmployeeTargets",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "GoogleSheetName",
                table: "KpiEmployeeTargets",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "GoogleSheetUrl",
                table: "KpiEmployeeTargets",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PenaltyTiersJson",
                table: "KpiEmployeeTargets",
                type: "character varying(2000)",
                maxLength: 2000,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "SyncIntervalMinutes",
                table: "KpiEmployeeTargets",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "Category",
                table: "Holidays",
                type: "character varying(100)",
                maxLength: 100,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AlterColumn<string>(
                name: "Template",
                table: "FingerprintTemplates",
                type: "text",
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "text",
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "Template",
                table: "FaceTemplates",
                type: "text",
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "text",
                oldNullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Department",
                table: "Employees",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "DirectManagerEmployeeId",
                table: "Employees",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "EducationLevel",
                table: "Employees",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Hometown",
                table: "Employees",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "Command",
                table: "DeviceCommands",
                type: "character varying(1000)",
                maxLength: 1000,
                nullable: false,
                oldClrType: typeof(string),
                oldType: "text");

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "CashTransactions",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "BankAccounts",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "EmployeeName",
                table: "AttendanceCorrectionRequests",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "Role",
                table: "AspNetUsers",
                type: "text",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "text");

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "AppSettings",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "PaidDate",
                table: "AdvanceRequests",
                type: "timestamp without time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PaymentMethod",
                table: "AdvanceRequests",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "DepartmentPermissions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    DepartmentId = table.Column<Guid>(type: "uuid", nullable: true),
                    PermissionId = table.Column<Guid>(type: "uuid", nullable: false),
                    IncludeChildren = table.Column<bool>(type: "boolean", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CanView = table.Column<bool>(type: "boolean", nullable: false),
                    CanCreate = table.Column<bool>(type: "boolean", nullable: false),
                    CanEdit = table.Column<bool>(type: "boolean", nullable: false),
                    CanDelete = table.Column<bool>(type: "boolean", nullable: false),
                    CanExport = table.Column<bool>(type: "boolean", nullable: false),
                    CanApprove = table.Column<bool>(type: "boolean", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    GrantedBy = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    Note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DepartmentPermissions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DepartmentPermissions_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_DepartmentPermissions_Departments_DepartmentId",
                        column: x => x.DepartmentId,
                        principalTable: "Departments",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_DepartmentPermissions_Permissions_PermissionId",
                        column: x => x.PermissionId,
                        principalTable: "Permissions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_DepartmentPermissions_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "EmployeeTaxDeductions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<Guid>(type: "uuid", nullable: false),
                    NumberOfDependents = table.Column<int>(type: "integer", nullable: false),
                    MandatoryInsurance = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    OtherExemptions = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EmployeeTaxDeductions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_EmployeeTaxDeductions_Employees_EmployeeId",
                        column: x => x.EmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_EmployeeTaxDeductions_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "EmployeeWorkingInfos",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    BalancedPaidLeaveDays = table.Column<decimal>(type: "numeric", nullable: false),
                    BalancedUnpaidLeaveDays = table.Column<decimal>(type: "numeric", nullable: false),
                    BalancedLateEarlyLeaveMinutes = table.Column<decimal>(type: "numeric", nullable: false),
                    StandardHoursPerDay = table.Column<int>(type: "integer", nullable: true),
                    WeeklyOffDays = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    PaidLeaveDaysPerYear = table.Column<decimal>(type: "numeric", nullable: true),
                    UnpaidLeaveDaysPerYear = table.Column<decimal>(type: "numeric", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EmployeeWorkingInfos", x => x.Id);
                    table.ForeignKey(
                        name: "FK_EmployeeWorkingInfos_AspNetUsers_EmployeeUserId",
                        column: x => x.EmployeeUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_EmployeeWorkingInfos_DeviceUsers_EmployeeId",
                        column: x => x.EmployeeId,
                        principalTable: "DeviceUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "NotificationCategories",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    DisplayName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Description = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    Icon = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    DisplayOrder = table.Column<int>(type: "integer", nullable: false),
                    IsSystem = table.Column<bool>(type: "boolean", nullable: false),
                    DefaultEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NotificationCategories", x => x.Id);
                    table.ForeignKey(
                        name: "FK_NotificationCategories_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "NotificationPreferences",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CategoryCode = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    IsEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NotificationPreferences", x => x.Id);
                    table.ForeignKey(
                        name: "FK_NotificationPreferences_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_NotificationPreferences_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "PenaltyTickets",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TicketCode = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    EmployeeId = table.Column<Guid>(type: "uuid", nullable: false),
                    Type = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    ViolationDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    MinutesLateOrEarly = table.Column<int>(type: "integer", nullable: true),
                    ShiftStartTime = table.Column<TimeSpan>(type: "interval", nullable: true),
                    ShiftEndTime = table.Column<TimeSpan>(type: "interval", nullable: true),
                    ActualPunchTime = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    PenaltyTier = table.Column<int>(type: "integer", nullable: false),
                    RepeatCountInMonth = table.Column<int>(type: "integer", nullable: true),
                    Description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CancellationReason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    ProcessedById = table.Column<Guid>(type: "uuid", nullable: true),
                    ProcessedDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    CashTransactionId = table.Column<Guid>(type: "uuid", nullable: true),
                    ShiftId = table.Column<Guid>(type: "uuid", nullable: true),
                    AttendanceId = table.Column<Guid>(type: "uuid", nullable: true),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    LastModified = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    LastModifiedBy = table.Column<string>(type: "text", nullable: true),
                    Deleted = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    DeletedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PenaltyTickets", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PenaltyTickets_AspNetUsers_ProcessedById",
                        column: x => x.ProcessedById,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_PenaltyTickets_AttendanceLogs_AttendanceId",
                        column: x => x.AttendanceId,
                        principalTable: "AttendanceLogs",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_PenaltyTickets_CashTransactions_CashTransactionId",
                        column: x => x.CashTransactionId,
                        principalTable: "CashTransactions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_PenaltyTickets_Employees_EmployeeId",
                        column: x => x.EmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_PenaltyTickets_Shifts_ShiftId",
                        column: x => x.ShiftId,
                        principalTable: "Shifts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_PenaltyTickets_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "TaskEvaluations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TaskId = table.Column<Guid>(type: "uuid", nullable: false),
                    EvaluatorId = table.Column<Guid>(type: "uuid", nullable: false),
                    QualityScore = table.Column<int>(type: "integer", nullable: false),
                    TimelinessScore = table.Column<int>(type: "integer", nullable: false),
                    OverallScore = table.Column<int>(type: "integer", nullable: false),
                    Comment = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TaskEvaluations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_TaskEvaluations_AspNetUsers_EvaluatorId",
                        column: x => x.EvaluatorId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_TaskEvaluations_WorkTasks_TaskId",
                        column: x => x.TaskId,
                        principalTable: "WorkTasks",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TaskReminders",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    TaskId = table.Column<Guid>(type: "uuid", nullable: false),
                    SentById = table.Column<Guid>(type: "uuid", nullable: false),
                    SentToId = table.Column<Guid>(type: "uuid", nullable: false),
                    Message = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: false),
                    UrgencyLevel = table.Column<int>(type: "integer", nullable: false),
                    IsRead = table.Column<bool>(type: "boolean", nullable: false),
                    ReadAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TaskReminders", x => x.Id);
                    table.ForeignKey(
                        name: "FK_TaskReminders_AspNetUsers_SentById",
                        column: x => x.SentById,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_TaskReminders_Employees_SentToId",
                        column: x => x.SentToId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_TaskReminders_WorkTasks_TaskId",
                        column: x => x.TaskId,
                        principalTable: "WorkTasks",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.InsertData(
                table: "NotificationCategories",
                columns: new[] { "Id", "Code", "CreatedAt", "CreatedBy", "DefaultEnabled", "Description", "DisplayName", "DisplayOrder", "Icon", "IsSystem", "StoreId", "UpdatedAt", "UpdatedBy" },
                values: new object[,]
                {
                    { new Guid("a0000001-0000-0000-0000-000000000001"), "attendance", new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9554), null, true, "Thông báo chấm công vào/ra, trễ giờ, vắng mặt", "Chấm công", 1, "fingerprint", true, null, null, null },
                    { new Guid("a0000001-0000-0000-0000-000000000002"), "leave", new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9580), null, true, "Đơn nghỉ phép, duyệt/từ chối phép", "Nghỉ phép", 2, "event_busy", true, null, null, null },
                    { new Guid("a0000001-0000-0000-0000-000000000003"), "overtime", new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9583), null, true, "Đăng ký tăng ca, duyệt/từ chối tăng ca", "Tăng ca", 3, "more_time", true, null, null, null },
                    { new Guid("a0000001-0000-0000-0000-000000000004"), "payroll", new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9585), null, true, "Phiếu lương, thay đổi lương, thanh toán", "Lương & Phiếu lương", 4, "payments", true, null, null, null },
                    { new Guid("a0000001-0000-0000-0000-000000000005"), "task", new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9587), null, true, "Giao việc, cập nhật tiến độ, deadline", "Công việc", 5, "task_alt", true, null, null, null },
                    { new Guid("a0000001-0000-0000-0000-000000000006"), "approval", new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9589), null, true, "Yêu cầu phê duyệt, kết quả phê duyệt", "Phê duyệt", 6, "approval", true, null, null, null },
                    { new Guid("a0000001-0000-0000-0000-000000000007"), "device", new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9591), null, true, "Trạng thái máy chấm công online/offline", "Thiết bị", 7, "router", true, null, null, null },
                    { new Guid("a0000001-0000-0000-0000-000000000008"), "hr", new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9592), null, true, "Hợp đồng, bổ nhiệm, thuyên chuyển", "Nhân sự", 8, "people", true, null, null, null },
                    { new Guid("a0000001-0000-0000-0000-000000000009"), "system", new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9594), null, true, "Cập nhật hệ thống, bảo trì, thông báo chung", "Hệ thống", 9, "settings", true, null, null, null }
                });

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3345));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3366));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3368));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3370));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3372));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3373));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3375));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3377));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3379));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3380));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3382));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3383));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3385));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3386));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3388));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3390));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3391));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3393));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3394));

            migrationBuilder.InsertData(
                table: "Permissions",
                columns: new[] { "Id", "CreatedAt", "CreatedBy", "Description", "DisplayOrder", "Module", "ModuleDisplayName", "UpdatedAt", "UpdatedBy" },
                values: new object[,]
                {
                    { new Guid("11111111-1111-1111-1111-111111111020"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3396), null, "Quản lý phòng ban", 20, "Department", "Phòng ban", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111021"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3416), null, "Quản lý tăng ca", 21, "Overtime", "Tăng ca", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111022"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3440), null, "Quản lý điều chỉnh chấm công", 22, "AttendanceCorrection", "Điều chỉnh CC", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111023"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3451), null, "Quản lý lịch làm việc", 23, "WorkSchedule", "Lịch làm việc", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111024"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3453), null, "Quản lý đổi ca", 24, "ShiftSwap", "Đổi ca", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111025"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3454), null, "Quản lý mẫu ca làm việc", 25, "ShiftTemplate", "Mẫu ca", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111026"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3456), null, "Quản lý bậc lương theo ca", 26, "ShiftSalaryLevel", "Bậc lương ca", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111027"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3458), null, "Quản lý phúc lợi", 27, "Benefit", "Phúc lợi", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111028"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3459), null, "Quản lý giao dịch", 28, "Transaction", "Giao dịch", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111029"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3461), null, "Quản lý thu chi tiền mặt", 29, "CashTransaction", "Thu chi tiền mặt", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111030"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3462), null, "Quản lý tài khoản ngân hàng", 30, "BankAccount", "Tài khoản NH", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111031"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3464), null, "Quản lý hồ sơ nhân sự", 31, "HrDocument", "Hồ sơ nhân sự", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111032"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3465), null, "Quản lý công việc", 32, "Task", "Công việc", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111033"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3467), null, "Quản lý KPI", 33, "KPI", "Đánh giá KPI", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111034"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3468), null, "Quản lý tài sản", 34, "Asset", "Tài sản", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111035"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3471), null, "Quản lý vùng địa lý", 35, "Geofence", "Vùng địa lý", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111036"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3472), null, "Quản lý sơ đồ tổ chức", 36, "OrgChart", "Sơ đồ tổ chức", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111037"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3474), null, "Quản lý chi nhánh", 37, "Branch", "Chi nhánh", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111038"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3475), null, "Quản lý truyền thông nội bộ", 38, "Communication", "Truyền thông", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111039"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3477), null, "Quản lý user trên máy chấm công", 39, "DeviceUser", "User máy CC", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111040"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3478), null, "Quản lý tài khoản hệ thống", 40, "UserManagement", "Quản lý user", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111041"), new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3480), null, "Phân quyền theo phòng ban", 41, "DepartmentPermission", "PQ Phòng ban", null, null }
                });

            migrationBuilder.CreateIndex(
                name: "IX_WorkSchedules_Employee_Date",
                table: "WorkSchedules",
                columns: new[] { "EmployeeId", "Date" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_TransactionCategories_StoreId",
                table: "TransactionCategories",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_SystemConfigurations_StoreId",
                table: "SystemConfigurations",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Notifications_CategoryCode",
                table: "Notifications",
                column: "CategoryCode");

            migrationBuilder.CreateIndex(
                name: "IX_Notifications_Store_Timestamp",
                table: "Notifications",
                columns: new[] { "StoreId", "Timestamp" });

            migrationBuilder.CreateIndex(
                name: "IX_Notifications_Store_User_Read",
                table: "Notifications",
                columns: new[] { "StoreId", "TargetUserId", "IsRead" });

            migrationBuilder.CreateIndex(
                name: "IX_Leaves_ShiftId",
                table: "Leaves",
                column: "ShiftId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Leaves_Store_Dates",
                table: "Leaves",
                columns: new[] { "StoreId", "StartDate", "EndDate" });

            migrationBuilder.CreateIndex(
                name: "IX_KpiEmployeeTarget_Employee_Period",
                table: "KpiEmployeeTargets",
                columns: new[] { "EmployeeId", "KpiPeriodId" });

            migrationBuilder.CreateIndex(
                name: "IX_Employees_DirectManagerEmployeeId",
                table: "Employees",
                column: "DirectManagerEmployeeId");

            migrationBuilder.CreateIndex(
                name: "IX_CashTransactions_Store_Status_Date",
                table: "CashTransactions",
                columns: new[] { "StoreId", "Status", "TransactionDate" });

            migrationBuilder.CreateIndex(
                name: "IX_BankAccounts_StoreId",
                table: "BankAccounts",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Attendance_Device_Time",
                table: "AttendanceLogs",
                columns: new[] { "DeviceId", "AttendanceTime" });

            migrationBuilder.CreateIndex(
                name: "IX_Attendance_Employee_Time",
                table: "AttendanceLogs",
                columns: new[] { "EmployeeId", "AttendanceTime" });

            migrationBuilder.CreateIndex(
                name: "IX_Attendance_PIN_Time",
                table: "AttendanceLogs",
                columns: new[] { "PIN", "AttendanceTime" });

            migrationBuilder.CreateIndex(
                name: "IX_AppSettings_StoreId",
                table: "AppSettings",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_DepartmentPermissions_DepartmentId",
                table: "DepartmentPermissions",
                column: "DepartmentId");

            migrationBuilder.CreateIndex(
                name: "IX_DepartmentPermissions_PermissionId",
                table: "DepartmentPermissions",
                column: "PermissionId");

            migrationBuilder.CreateIndex(
                name: "IX_DepartmentPermissions_StoreId",
                table: "DepartmentPermissions",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_DepartmentPermissions_UserId",
                table: "DepartmentPermissions",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_DepartmentPermissions_UserId_DepartmentId_PermissionId_Stor~",
                table: "DepartmentPermissions",
                columns: new[] { "UserId", "DepartmentId", "PermissionId", "StoreId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeTaxDeductions_EmployeeId_StoreId",
                table: "EmployeeTaxDeductions",
                columns: new[] { "EmployeeId", "StoreId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeTaxDeductions_StoreId",
                table: "EmployeeTaxDeductions",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeWorkingInfos_EmployeeId",
                table: "EmployeeWorkingInfos",
                column: "EmployeeId");

            migrationBuilder.CreateIndex(
                name: "IX_EmployeeWorkingInfos_EmployeeUserId",
                table: "EmployeeWorkingInfos",
                column: "EmployeeUserId");

            migrationBuilder.CreateIndex(
                name: "IX_NotificationCategories_Code",
                table: "NotificationCategories",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_NotificationCategories_StoreId",
                table: "NotificationCategories",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_NotificationPreferences_StoreId",
                table: "NotificationPreferences",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_NotificationPreferences_User_Category_Store",
                table: "NotificationPreferences",
                columns: new[] { "UserId", "CategoryCode", "StoreId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_NotificationPreferences_UserId",
                table: "NotificationPreferences",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_PenaltyTickets_AttendanceId",
                table: "PenaltyTickets",
                column: "AttendanceId");

            migrationBuilder.CreateIndex(
                name: "IX_PenaltyTickets_CashTransactionId",
                table: "PenaltyTickets",
                column: "CashTransactionId");

            migrationBuilder.CreateIndex(
                name: "IX_PenaltyTickets_EmployeeId_ViolationDate",
                table: "PenaltyTickets",
                columns: new[] { "EmployeeId", "ViolationDate" });

            migrationBuilder.CreateIndex(
                name: "IX_PenaltyTickets_ProcessedById",
                table: "PenaltyTickets",
                column: "ProcessedById");

            migrationBuilder.CreateIndex(
                name: "IX_PenaltyTickets_ShiftId",
                table: "PenaltyTickets",
                column: "ShiftId");

            migrationBuilder.CreateIndex(
                name: "IX_PenaltyTickets_StoreId_Status_ViolationDate",
                table: "PenaltyTickets",
                columns: new[] { "StoreId", "Status", "ViolationDate" });

            migrationBuilder.CreateIndex(
                name: "IX_PenaltyTickets_TicketCode",
                table: "PenaltyTickets",
                column: "TicketCode",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_TaskEvaluations_EvaluatorId",
                table: "TaskEvaluations",
                column: "EvaluatorId");

            migrationBuilder.CreateIndex(
                name: "IX_TaskEvaluations_Task_Evaluator",
                table: "TaskEvaluations",
                columns: new[] { "TaskId", "EvaluatorId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_TaskEvaluations_TaskId",
                table: "TaskEvaluations",
                column: "TaskId");

            migrationBuilder.CreateIndex(
                name: "IX_TaskReminders_SentById",
                table: "TaskReminders",
                column: "SentById");

            migrationBuilder.CreateIndex(
                name: "IX_TaskReminders_SentToId",
                table: "TaskReminders",
                column: "SentToId");

            migrationBuilder.CreateIndex(
                name: "IX_TaskReminders_TaskId",
                table: "TaskReminders",
                column: "TaskId");

            migrationBuilder.AddForeignKey(
                name: "FK_AppSettings_Stores_StoreId",
                table: "AppSettings",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_AspNetUsers_ApprovedById",
                table: "AttendanceCorrectionRequests",
                column: "ApprovedById",
                principalTable: "AspNetUsers",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_AspNetUsers_EmployeeUserId",
                table: "AttendanceCorrectionRequests",
                column: "EmployeeUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId",
                table: "AttendanceCorrectionRequests",
                column: "AttendanceId",
                principalTable: "AttendanceLogs",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_BankAccounts_Stores_StoreId",
                table: "BankAccounts",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_CashTransactions_Stores_StoreId",
                table: "CashTransactions",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Employees_Branches_BranchId",
                table: "Employees",
                column: "BranchId",
                principalTable: "Branches",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Employees_Employees_DirectManagerEmployeeId",
                table: "Employees",
                column: "DirectManagerEmployeeId",
                principalTable: "Employees",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Leaves_Employees_ReplacementEmployeeId",
                table: "Leaves",
                column: "ReplacementEmployeeId",
                principalTable: "Employees",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Leaves_Shifts_ShiftId",
                table: "Leaves",
                column: "ShiftId",
                principalTable: "Shifts",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_PaymentTransactions_AspNetUsers_EmployeeUserId",
                table: "PaymentTransactions",
                column: "EmployeeUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_PaymentTransactions_Employees_EmployeeId",
                table: "PaymentTransactions",
                column: "EmployeeId",
                principalTable: "Employees",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckInAttendanceId",
                table: "Shifts",
                column: "CheckInAttendanceId",
                principalTable: "AttendanceLogs",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckOutAttendanceId",
                table: "Shifts",
                column: "CheckOutAttendanceId",
                principalTable: "AttendanceLogs",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_SystemConfigurations_Stores_StoreId",
                table: "SystemConfigurations",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_TransactionCategories_Stores_StoreId",
                table: "TransactionCategories",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AppSettings_Stores_StoreId",
                table: "AppSettings");

            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceCorrectionRequests_AspNetUsers_ApprovedById",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceCorrectionRequests_AspNetUsers_EmployeeUserId",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_BankAccounts_Stores_StoreId",
                table: "BankAccounts");

            migrationBuilder.DropForeignKey(
                name: "FK_CashTransactions_Stores_StoreId",
                table: "CashTransactions");

            migrationBuilder.DropForeignKey(
                name: "FK_Employees_Branches_BranchId",
                table: "Employees");

            migrationBuilder.DropForeignKey(
                name: "FK_Employees_Employees_DirectManagerEmployeeId",
                table: "Employees");

            migrationBuilder.DropForeignKey(
                name: "FK_Leaves_Employees_ReplacementEmployeeId",
                table: "Leaves");

            migrationBuilder.DropForeignKey(
                name: "FK_Leaves_Shifts_ShiftId",
                table: "Leaves");

            migrationBuilder.DropForeignKey(
                name: "FK_PaymentTransactions_AspNetUsers_EmployeeUserId",
                table: "PaymentTransactions");

            migrationBuilder.DropForeignKey(
                name: "FK_PaymentTransactions_Employees_EmployeeId",
                table: "PaymentTransactions");

            migrationBuilder.DropForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckInAttendanceId",
                table: "Shifts");

            migrationBuilder.DropForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckOutAttendanceId",
                table: "Shifts");

            migrationBuilder.DropForeignKey(
                name: "FK_SystemConfigurations_Stores_StoreId",
                table: "SystemConfigurations");

            migrationBuilder.DropForeignKey(
                name: "FK_TransactionCategories_Stores_StoreId",
                table: "TransactionCategories");

            migrationBuilder.DropTable(
                name: "DepartmentPermissions");

            migrationBuilder.DropTable(
                name: "EmployeeTaxDeductions");

            migrationBuilder.DropTable(
                name: "EmployeeWorkingInfos");

            migrationBuilder.DropTable(
                name: "NotificationCategories");

            migrationBuilder.DropTable(
                name: "NotificationPreferences");

            migrationBuilder.DropTable(
                name: "PenaltyTickets");

            migrationBuilder.DropTable(
                name: "TaskEvaluations");

            migrationBuilder.DropTable(
                name: "TaskReminders");

            migrationBuilder.DropIndex(
                name: "IX_WorkSchedules_Employee_Date",
                table: "WorkSchedules");

            migrationBuilder.DropIndex(
                name: "IX_TransactionCategories_StoreId",
                table: "TransactionCategories");

            migrationBuilder.DropIndex(
                name: "IX_SystemConfigurations_StoreId",
                table: "SystemConfigurations");

            migrationBuilder.DropIndex(
                name: "IX_Notifications_CategoryCode",
                table: "Notifications");

            migrationBuilder.DropIndex(
                name: "IX_Notifications_Store_Timestamp",
                table: "Notifications");

            migrationBuilder.DropIndex(
                name: "IX_Notifications_Store_User_Read",
                table: "Notifications");

            migrationBuilder.DropIndex(
                name: "IX_Leaves_ShiftId",
                table: "Leaves");

            migrationBuilder.DropIndex(
                name: "IX_Leaves_Store_Dates",
                table: "Leaves");

            migrationBuilder.DropIndex(
                name: "IX_KpiEmployeeTarget_Employee_Period",
                table: "KpiEmployeeTargets");

            migrationBuilder.DropIndex(
                name: "IX_Employees_DirectManagerEmployeeId",
                table: "Employees");

            migrationBuilder.DropIndex(
                name: "IX_CashTransactions_Store_Status_Date",
                table: "CashTransactions");

            migrationBuilder.DropIndex(
                name: "IX_BankAccounts_StoreId",
                table: "BankAccounts");

            migrationBuilder.DropIndex(
                name: "IX_Attendance_Device_Time",
                table: "AttendanceLogs");

            migrationBuilder.DropIndex(
                name: "IX_Attendance_Employee_Time",
                table: "AttendanceLogs");

            migrationBuilder.DropIndex(
                name: "IX_Attendance_PIN_Time",
                table: "AttendanceLogs");

            migrationBuilder.DropIndex(
                name: "IX_AppSettings_StoreId",
                table: "AppSettings");

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111020"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111021"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111022"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111023"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111024"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111025"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111026"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111027"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111028"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111029"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111030"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111031"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111032"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111033"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111034"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111035"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111036"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111037"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111038"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111039"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111040"));

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111041"));

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "TransactionCategories");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "SystemConfigurations");

            migrationBuilder.DropColumn(
                name: "AttendanceMode",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "CompletionSalary",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "DailyFixedRate",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "FixedShiftRate",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "HolidayOvertimeDailyRate",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "HolidayOvertimeType",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "HourlyOvertimeFixedRate",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "HourlyOvertimeType",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "InsuranceSalary",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "PaidLeaveType",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "ShiftSalaryType",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "ShiftsPerDay",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "CategoryCode",
                table: "Notifications");

            migrationBuilder.DropColumn(
                name: "EmployeeId",
                table: "Leaves");

            migrationBuilder.DropColumn(
                name: "ShiftId",
                table: "Leaves");

            migrationBuilder.DropColumn(
                name: "AutoSyncEnabled",
                table: "KpiPeriods");

            migrationBuilder.DropColumn(
                name: "AutoSyncTimeSlots",
                table: "KpiPeriods");

            migrationBuilder.DropColumn(
                name: "AutoSyncEnabled",
                table: "KpiEmployeeTargets");

            migrationBuilder.DropColumn(
                name: "GoogleCellPosition",
                table: "KpiEmployeeTargets");

            migrationBuilder.DropColumn(
                name: "GoogleSheetName",
                table: "KpiEmployeeTargets");

            migrationBuilder.DropColumn(
                name: "GoogleSheetUrl",
                table: "KpiEmployeeTargets");

            migrationBuilder.DropColumn(
                name: "PenaltyTiersJson",
                table: "KpiEmployeeTargets");

            migrationBuilder.DropColumn(
                name: "SyncIntervalMinutes",
                table: "KpiEmployeeTargets");

            migrationBuilder.DropColumn(
                name: "Category",
                table: "Holidays");

            migrationBuilder.DropColumn(
                name: "Department",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "DirectManagerEmployeeId",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "EducationLevel",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "Hometown",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "CashTransactions");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "BankAccounts");

            migrationBuilder.DropColumn(
                name: "EmployeeName",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "AppSettings");

            migrationBuilder.DropColumn(
                name: "PaidDate",
                table: "AdvanceRequests");

            migrationBuilder.DropColumn(
                name: "PaymentMethod",
                table: "AdvanceRequests");

            migrationBuilder.RenameIndex(
                name: "IX_WorkSchedules_EmployeeUserId",
                table: "WorkSchedules",
                newName: "IX_WorkSchedules_EmployeeId");

            migrationBuilder.RenameIndex(
                name: "IX_Stores_Code",
                table: "Stores",
                newName: "IX_Store_Code");

            migrationBuilder.RenameIndex(
                name: "IX_Stores_AgentId",
                table: "Stores",
                newName: "IX_Store_AgentId");

            migrationBuilder.RenameColumn(
                name: "Description",
                table: "ShiftTemplates",
                newName: "AssignedEmployeeIds");

            migrationBuilder.RenameIndex(
                name: "IX_ScheduleRegistrations_EmployeeUserId",
                table: "ScheduleRegistrations",
                newName: "IX_ScheduleRegistrations_EmployeeId");

            migrationBuilder.RenameColumn(
                name: "SocialInsuranceType",
                table: "SalaryProfiles",
                newName: "CustomWorkDays");

            migrationBuilder.RenameIndex(
                name: "IX_KpiEmployeeTarget_PeriodId",
                table: "KpiEmployeeTargets",
                newName: "IX_KpiEmployeeTargets_KpiPeriodId");

            migrationBuilder.RenameIndex(
                name: "IX_Devices_StoreId",
                table: "Devices",
                newName: "IX_Device_StoreId");

            migrationBuilder.RenameIndex(
                name: "IX_Devices_SerialNumber",
                table: "Devices",
                newName: "IX_Device_SerialNumber");

            migrationBuilder.RenameIndex(
                name: "IX_AttendanceLogs_PIN",
                table: "AttendanceLogs",
                newName: "IX_Attendance_PIN");

            migrationBuilder.RenameIndex(
                name: "IX_AttendanceLogs_EmployeeId",
                table: "AttendanceLogs",
                newName: "IX_Attendance_EmployeeId");

            migrationBuilder.RenameIndex(
                name: "IX_AttendanceLogs_DeviceId",
                table: "AttendanceLogs",
                newName: "IX_Attendance_DeviceId");

            migrationBuilder.RenameColumn(
                name: "EmployeeCode",
                table: "AttendanceCorrectionRequests",
                newName: "NewType");

            migrationBuilder.AlterColumn<string>(
                name: "LockReason",
                table: "Stores",
                type: "character varying(500)",
                maxLength: 500,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "text",
                oldNullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "LicenseKey",
                table: "Stores",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "text",
                oldNullable: true);

            migrationBuilder.AddColumn<int>(
                name: "EarlyCheckInMinutes",
                table: "ShiftTemplates",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "EarlyLeaveGraceMinutes",
                table: "ShiftTemplates",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "LateGraceMinutes",
                table: "ShiftTemplates",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "OvertimeMinutesThreshold",
                table: "ShiftTemplates",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<decimal>(
                name: "MaxBhtnRegionI",
                table: "InsuranceSettings",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "MaxBhtnRegionII",
                table: "InsuranceSettings",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "MaxBhtnRegionIII",
                table: "InsuranceSettings",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<decimal>(
                name: "MaxBhtnRegionIV",
                table: "InsuranceSettings",
                type: "numeric",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AlterColumn<string>(
                name: "Template",
                table: "FingerprintTemplates",
                type: "text",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "text");

            migrationBuilder.AlterColumn<string>(
                name: "Template",
                table: "FaceTemplates",
                type: "text",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "text");

            migrationBuilder.AddColumn<string>(
                name: "DisplayName",
                table: "DeviceUsers",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "Command",
                table: "DeviceCommands",
                type: "text",
                nullable: false,
                oldClrType: typeof(string),
                oldType: "character varying(1000)",
                oldMaxLength: 1000);

            migrationBuilder.AddColumn<Guid>(
                name: "CreatedAttendanceId",
                table: "AttendanceCorrectionRequests",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "CreatedByUserId",
                table: "AttendanceCorrectionRequests",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OriginalAttendanceState",
                table: "AttendanceCorrectionRequests",
                type: "character varying(2000)",
                maxLength: 2000,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "StoredEmployeeCode",
                table: "AttendanceCorrectionRequests",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "StoredEmployeeName",
                table: "AttendanceCorrectionRequests",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "StoredPin",
                table: "AttendanceCorrectionRequests",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AlterColumn<string>(
                name: "Role",
                table: "AspNetUsers",
                type: "text",
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "text",
                oldNullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DailyCalcMethod",
                table: "Allowances",
                type: "character varying(50)",
                maxLength: 50,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "StandardWorkDays",
                table: "Allowances",
                type: "integer",
                nullable: true);

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6384));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6544));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6548));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6555));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6557));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6562));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6568));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6572));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6574));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6578));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6579));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6582));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6588));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6590));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6594));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6596));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6598));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6605));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 18, 17, 22, 287, DateTimeKind.Local).AddTicks(6610));

            migrationBuilder.CreateIndex(
                name: "IX_WorkSchedules_Employee_Date_Shift",
                table: "WorkSchedules",
                columns: new[] { "EmployeeId", "Date", "ShiftId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Store_ExpiryDate",
                table: "Stores",
                column: "ExpiryDate");

            migrationBuilder.CreateIndex(
                name: "IX_Store_IsActive",
                table: "Stores",
                column: "IsActive");

            migrationBuilder.CreateIndex(
                name: "IX_Store_IsActive_IsLocked",
                table: "Stores",
                columns: new[] { "IsActive", "IsLocked" });

            migrationBuilder.CreateIndex(
                name: "IX_Store_IsLocked",
                table: "Stores",
                column: "IsLocked");

            migrationBuilder.CreateIndex(
                name: "IX_Leaves_StoreId",
                table: "Leaves",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_KpiEmployeeTargets_EmployeeId",
                table: "KpiEmployeeTargets",
                column: "EmployeeId");

            migrationBuilder.CreateIndex(
                name: "IX_Device_DeviceStatus",
                table: "Devices",
                column: "DeviceStatus");

            migrationBuilder.CreateIndex(
                name: "IX_Device_IsClaimed",
                table: "Devices",
                column: "IsClaimed");

            migrationBuilder.CreateIndex(
                name: "IX_Device_LastOnline",
                table: "Devices",
                column: "LastOnline",
                descending: new bool[0]);

            migrationBuilder.CreateIndex(
                name: "IX_Device_StoreId_DeviceStatus",
                table: "Devices",
                columns: new[] { "StoreId", "DeviceStatus" });

            migrationBuilder.CreateIndex(
                name: "IX_Attendance_AttendanceTime",
                table: "AttendanceLogs",
                column: "AttendanceTime",
                descending: new bool[0]);

            migrationBuilder.CreateIndex(
                name: "IX_Attendance_DeviceId_AttendanceTime",
                table: "AttendanceLogs",
                columns: new[] { "DeviceId", "AttendanceTime" },
                descending: new[] { false, true });

            migrationBuilder.CreateIndex(
                name: "IX_Attendance_EmployeeId_AttendanceTime",
                table: "AttendanceLogs",
                columns: new[] { "EmployeeId", "AttendanceTime" },
                descending: new[] { false, true });

            migrationBuilder.CreateIndex(
                name: "IX_AttendanceCorrectionRequests_CreatedByUserId",
                table: "AttendanceCorrectionRequests",
                column: "CreatedByUserId");

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_AspNetUsers_ApprovedById",
                table: "AttendanceCorrectionRequests",
                column: "ApprovedById",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_AspNetUsers_CreatedByUserId",
                table: "AttendanceCorrectionRequests",
                column: "CreatedByUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_AspNetUsers_EmployeeUserId",
                table: "AttendanceCorrectionRequests",
                column: "EmployeeUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId",
                table: "AttendanceCorrectionRequests",
                column: "AttendanceId",
                principalTable: "AttendanceLogs",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_Employees_Branches_BranchId",
                table: "Employees",
                column: "BranchId",
                principalTable: "Branches",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_Leaves_Employees_ReplacementEmployeeId",
                table: "Leaves",
                column: "ReplacementEmployeeId",
                principalTable: "Employees",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_PaymentTransactions_AspNetUsers_EmployeeUserId",
                table: "PaymentTransactions",
                column: "EmployeeUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_PaymentTransactions_Employees_EmployeeId",
                table: "PaymentTransactions",
                column: "EmployeeId",
                principalTable: "Employees",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckInAttendanceId",
                table: "Shifts",
                column: "CheckInAttendanceId",
                principalTable: "AttendanceLogs",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckOutAttendanceId",
                table: "Shifts",
                column: "CheckOutAttendanceId",
                principalTable: "AttendanceLogs",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }
    }
}
