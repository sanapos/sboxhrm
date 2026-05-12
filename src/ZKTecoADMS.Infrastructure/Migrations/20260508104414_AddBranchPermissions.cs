using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddBranchPermissions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AssetInventories_AspNetUsers_ResponsibleUserId",
                table: "AssetInventories");

            migrationBuilder.DropForeignKey(
                name: "FK_Assets_AspNetUsers_CurrentAssigneeId",
                table: "Assets");

            migrationBuilder.DropForeignKey(
                name: "FK_AssetTransfers_AspNetUsers_FromUserId",
                table: "AssetTransfers");

            migrationBuilder.DropForeignKey(
                name: "FK_AssetTransfers_AspNetUsers_ToUserId",
                table: "AssetTransfers");

            migrationBuilder.DropForeignKey(
                name: "FK_ShiftTemplates_AspNetUsers_ManagerId",
                table: "ShiftTemplates");

            migrationBuilder.DropForeignKey(
                name: "FK_ShiftTemplates_Stores_StoreId",
                table: "ShiftTemplates");

            migrationBuilder.DropIndex(
                name: "IX_Employees_CompanyEmail",
                table: "Employees");

            migrationBuilder.DropIndex(
                name: "IX_Employees_EmployeeCode",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "PlainTextPassword",
                table: "AspNetUsers");

            migrationBuilder.AddColumn<int>(
                name: "CommentType",
                table: "TaskComments",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "ImageUrls",
                table: "TaskComments",
                type: "character varying(4000)",
                maxLength: 4000,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "LinkUrls",
                table: "TaskComments",
                type: "character varying(4000)",
                maxLength: 4000,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ProgressSnapshot",
                table: "TaskComments",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Code",
                table: "ShiftTemplates",
                type: "text",
                nullable: true);

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

            migrationBuilder.AddColumn<TimeSpan>(
                name: "OvernightCutoffTime",
                table: "ShiftTemplates",
                type: "interval",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "OvertimeMinutesThreshold",
                table: "ShiftTemplates",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "ShiftType",
                table: "ShiftTemplates",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "Allowances",
                table: "Payslips",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "HealthInsurance",
                table: "Payslips",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "SocialInsurance",
                table: "Payslips",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "Tax",
                table: "Payslips",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "UnemploymentInsurance",
                table: "Payslips",
                type: "numeric",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "CurrentApprovalStep",
                table: "Leaves",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "TotalApprovalLevels",
                table: "Leaves",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "DeviceType",
                table: "Devices",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<Guid>(
                name: "MobileAttendanceRecordId",
                table: "AttendanceLogs",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "CurrentApprovalStep",
                table: "AttendanceCorrectionRequests",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "TotalApprovalLevels",
                table: "AttendanceCorrectionRequests",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "Color",
                table: "Assets",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "QrCode",
                table: "Assets",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Size",
                table: "Assets",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "StoredExpectedQuantity",
                table: "AssetInventoryItems",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "CurrentApprovalStep",
                table: "AdvanceRequests",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "TotalApprovalLevels",
                table: "AdvanceRequests",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateTable(
                name: "AdvanceApprovalRecords",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    AdvanceRequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    StepOrder = table.Column<int>(type: "integer", nullable: false),
                    StepName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    AssignedUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    AssignedUserName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ActualUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    ActualUserName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    Note = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    ActionDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AdvanceApprovalRecords", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AdvanceApprovalRecords_AdvanceRequests_AdvanceRequestId",
                        column: x => x.AdvanceRequestId,
                        principalTable: "AdvanceRequests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_AdvanceApprovalRecords_AspNetUsers_ActualUserId",
                        column: x => x.ActualUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_AdvanceApprovalRecords_AspNetUsers_AssignedUserId",
                        column: x => x.AssignedUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "AppBugReports",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    UserName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    UserEmail = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    StoreName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Type = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    Title = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    Content = table.Column<string>(type: "character varying(5000)", maxLength: 5000, nullable: false),
                    AppVersion = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    DeviceInfo = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    AdminNote = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    ResolvedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AppBugReports", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "AppPages",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Type = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    Title = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Content = table.Column<string>(type: "character varying(100000)", maxLength: 100000, nullable: true),
                    IsPublished = table.Column<bool>(type: "boolean", nullable: false),
                    UpdatedByName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AppPages", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ApprovalRecords",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CorrectionRequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    StepOrder = table.Column<int>(type: "integer", nullable: false),
                    StepName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    AssignedUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    AssignedUserName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ActualUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    ActualUserName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    Note = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    ActionDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ApprovalRecords", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ApprovalRecords_AspNetUsers_ActualUserId",
                        column: x => x.ActualUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_ApprovalRecords_AspNetUsers_AssignedUserId",
                        column: x => x.AssignedUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_ApprovalRecords_AttendanceCorrectionRequests_CorrectionRequ~",
                        column: x => x.CorrectionRequestId,
                        principalTable: "AttendanceCorrectionRequests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "AuthorizedMobileDevices",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    DeviceId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    DeviceName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    DeviceModel = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    OsVersion = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    EmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    IsAuthorized = table.Column<bool>(type: "boolean", nullable: false),
                    CanUseFaceId = table.Column<bool>(type: "boolean", nullable: false),
                    CanUseGps = table.Column<bool>(type: "boolean", nullable: false),
                    AllowOutsideCheckIn = table.Column<bool>(type: "boolean", nullable: false),
                    WifiBssid = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    AuthorizedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    LastUsedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
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
                    table.PrimaryKey("PK_AuthorizedMobileDevices", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AuthorizedMobileDevices_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "BranchPermissions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    BranchId = table.Column<Guid>(type: "uuid", nullable: true),
                    IncludeChildren = table.Column<bool>(type: "boolean", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CanView = table.Column<bool>(type: "boolean", nullable: false),
                    CanCreate = table.Column<bool>(type: "boolean", nullable: false),
                    CanEdit = table.Column<bool>(type: "boolean", nullable: false),
                    CanDelete = table.Column<bool>(type: "boolean", nullable: false),
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
                    table.PrimaryKey("PK_BranchPermissions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_BranchPermissions_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_BranchPermissions_Branches_BranchId",
                        column: x => x.BranchId,
                        principalTable: "Branches",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_BranchPermissions_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "DeviceChangeRequests",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    OldDeviceRecordId = table.Column<Guid>(type: "uuid", nullable: false),
                    OldDeviceName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    OldDeviceModel = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    NewDeviceId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    NewDeviceName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    NewDeviceModel = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    NewOsVersion = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    NewWifiBssid = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    NewFaceImagesJson = table.Column<string>(type: "text", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    Reason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    RequestedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    ApprovedBy = table.Column<Guid>(type: "uuid", nullable: true),
                    ApprovedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    RejectReason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
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
                    table.PrimaryKey("PK_DeviceChangeRequests", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DeviceChangeRequests_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "EmployeeLiveLocations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Latitude = table.Column<double>(type: "double precision", nullable: false),
                    Longitude = table.Column<double>(type: "double precision", nullable: false),
                    Accuracy = table.Column<double>(type: "double precision", nullable: true),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EmployeeLiveLocations", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Feedbacks",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    SenderEmployeeId = table.Column<Guid>(type: "uuid", nullable: true),
                    IsAnonymous = table.Column<bool>(type: "boolean", nullable: false),
                    RecipientEmployeeId = table.Column<Guid>(type: "uuid", nullable: true),
                    Title = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    Content = table.Column<string>(type: "character varying(5000)", maxLength: 5000, nullable: false),
                    ImageUrls = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    Category = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    Status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    Response = table.Column<string>(type: "character varying(5000)", maxLength: 5000, nullable: true),
                    RespondedByEmployeeId = table.Column<Guid>(type: "uuid", nullable: true),
                    RespondedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
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
                    table.PrimaryKey("PK_Feedbacks", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Feedbacks_Employees_RecipientEmployeeId",
                        column: x => x.RecipientEmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_Feedbacks_Employees_RespondedByEmployeeId",
                        column: x => x.RespondedByEmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_Feedbacks_Employees_SenderEmployeeId",
                        column: x => x.SenderEmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_Feedbacks_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "FieldLocations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    Address = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    ContactName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ContactPhone = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    ContactEmail = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Note = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    Latitude = table.Column<double>(type: "double precision", nullable: false),
                    Longitude = table.Column<double>(type: "double precision", nullable: false),
                    Radius = table.Column<int>(type: "integer", nullable: false),
                    PhotoUrlsJson = table.Column<string>(type: "text", nullable: true),
                    RegisteredByEmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    RegisteredByEmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Category = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    IsApproved = table.Column<bool>(type: "boolean", nullable: false),
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
                    table.PrimaryKey("PK_FieldLocations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_FieldLocations_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "JourneyTrackings",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    JourneyDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    StartTime = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    EndTime = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    Status = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    TotalDistanceKm = table.Column<double>(type: "double precision", nullable: false),
                    TotalTravelMinutes = table.Column<int>(type: "integer", nullable: false),
                    TotalOnSiteMinutes = table.Column<int>(type: "integer", nullable: false),
                    CheckedInCount = table.Column<int>(type: "integer", nullable: false),
                    AssignedCount = table.Column<int>(type: "integer", nullable: false),
                    RoutePointsJson = table.Column<string>(type: "text", nullable: true),
                    Note = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    ReviewedBy = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ReviewedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    ReviewNote = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
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
                    table.PrimaryKey("PK_JourneyTrackings", x => x.Id);
                    table.ForeignKey(
                        name: "FK_JourneyTrackings_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "LeaveApprovalRecords",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    LeaveId = table.Column<Guid>(type: "uuid", nullable: false),
                    StepOrder = table.Column<int>(type: "integer", nullable: false),
                    StepName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    AssignedUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    AssignedUserName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ActualUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    ActualUserName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    Note = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    ActionDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LeaveApprovalRecords", x => x.Id);
                    table.ForeignKey(
                        name: "FK_LeaveApprovalRecords_AspNetUsers_ActualUserId",
                        column: x => x.ActualUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LeaveApprovalRecords_AspNetUsers_AssignedUserId",
                        column: x => x.AssignedUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_LeaveApprovalRecords_Leaves_LeaveId",
                        column: x => x.LeaveId,
                        principalTable: "Leaves",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "MaintenanceWindows",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Title = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Message = table.Column<string>(type: "text", nullable: false),
                    StartAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    EndAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    AffectedModulesJson = table.Column<string>(type: "jsonb", nullable: true),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    BlockAccess = table.Column<bool>(type: "boolean", nullable: false),
                    NotifyBeforeMinutesCsv = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    NotifiedMinutesCsv = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    StartNotified = table.Column<bool>(type: "boolean", nullable: false),
                    EndNotified = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedByUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MaintenanceWindows", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "MealDishes",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Category = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
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
                    table.PrimaryKey("PK_MealDishes", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MealDishes_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "MealSessions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    StartTime = table.Column<TimeSpan>(type: "interval", nullable: false),
                    EndTime = table.Column<TimeSpan>(type: "interval", nullable: false),
                    Description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    PricePerMeal = table.Column<decimal>(type: "numeric", nullable: false),
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
                    table.PrimaryKey("PK_MealSessions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MealSessions_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "MobileAttendanceRecords",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    OdooEmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    PunchTime = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    PunchType = table.Column<int>(type: "integer", nullable: false),
                    Latitude = table.Column<double>(type: "double precision", nullable: true),
                    Longitude = table.Column<double>(type: "double precision", nullable: true),
                    LocationName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    DistanceFromLocation = table.Column<double>(type: "double precision", nullable: true),
                    FaceImageUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    FaceMatchScore = table.Column<double>(type: "double precision", nullable: true),
                    VerifyMethod = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    ApprovedBy = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ApprovedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    RejectReason = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    DeviceId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    DeviceName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    WifiSsid = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    WifiBssid = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    WifiIpAddress = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
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
                    table.PrimaryKey("PK_MobileAttendanceRecords", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MobileAttendanceRecords_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "MobileAttendanceSettings",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    EnableFaceId = table.Column<bool>(type: "boolean", nullable: false),
                    EnableGps = table.Column<bool>(type: "boolean", nullable: false),
                    EnableWifi = table.Column<bool>(type: "boolean", nullable: false),
                    EnableLivenessDetection = table.Column<bool>(type: "boolean", nullable: false),
                    VerificationMode = table.Column<string>(type: "text", nullable: false),
                    GpsRadiusMeters = table.Column<int>(type: "integer", nullable: false),
                    MinFaceMatchScore = table.Column<double>(type: "double precision", nullable: false),
                    AutoApproveInRange = table.Column<bool>(type: "boolean", nullable: false),
                    AllowManualApproval = table.Column<bool>(type: "boolean", nullable: false),
                    MaxPhotosPerRegistration = table.Column<int>(type: "integer", nullable: false),
                    MaxPunchesPerDay = table.Column<int>(type: "integer", nullable: false),
                    RequirePhotoProof = table.Column<bool>(type: "boolean", nullable: false),
                    MinPunchIntervalMinutes = table.Column<int>(type: "integer", nullable: false),
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
                    table.PrimaryKey("PK_MobileAttendanceSettings", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MobileAttendanceSettings_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "MobileFaceRegistrations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    OdooEmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    EmployeeCode = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    Department = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    FaceImagesJson = table.Column<string>(type: "text", nullable: false),
                    IsVerified = table.Column<bool>(type: "boolean", nullable: false),
                    RegisteredAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    LastVerifiedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
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
                    table.PrimaryKey("PK_MobileFaceRegistrations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MobileFaceRegistrations_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "MobileWorkLocations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Address = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    Latitude = table.Column<double>(type: "double precision", nullable: false),
                    Longitude = table.Column<double>(type: "double precision", nullable: false),
                    Radius = table.Column<int>(type: "integer", nullable: false),
                    AutoApproveInRange = table.Column<bool>(type: "boolean", nullable: false),
                    WifiSsid = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    WifiBssid = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    AllowedIpRange = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
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
                    table.PrimaryKey("PK_MobileWorkLocations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MobileWorkLocations_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "NotificationTemplates",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Title = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Body = table.Column<string>(type: "text", nullable: false),
                    VariablesJson = table.Column<string>(type: "jsonb", nullable: true),
                    Channels = table.Column<int>(type: "integer", nullable: false),
                    Locale = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NotificationTemplates", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "ProductGroups",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
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
                    table.PrimaryKey("PK_ProductGroups", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ProductGroups_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "ShiftStaffingQuotas",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    ShiftTemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                    Department = table.Column<string>(type: "text", nullable: true),
                    MinEmployees = table.Column<int>(type: "integer", nullable: false),
                    MaxEmployees = table.Column<int>(type: "integer", nullable: false),
                    WarningThreshold = table.Column<int>(type: "integer", nullable: false),
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
                    table.PrimaryKey("PK_ShiftStaffingQuotas", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ShiftStaffingQuotas_ShiftTemplates_ShiftTemplateId",
                        column: x => x.ShiftTemplateId,
                        principalTable: "ShiftTemplates",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ShiftStaffingQuotas_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "StockTransactions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    AssetId = table.Column<Guid>(type: "uuid", nullable: false),
                    TransactionType = table.Column<int>(type: "integer", nullable: false),
                    Quantity = table.Column<int>(type: "integer", nullable: false),
                    BalanceAfter = table.Column<int>(type: "integer", nullable: false),
                    Reason = table.Column<string>(type: "text", nullable: true),
                    ReferenceCode = table.Column<string>(type: "text", nullable: true),
                    RelatedInventoryId = table.Column<Guid>(type: "uuid", nullable: true),
                    PerformedById = table.Column<Guid>(type: "uuid", nullable: true),
                    Notes = table.Column<string>(type: "text", nullable: true),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    TransactionDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StockTransactions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_StockTransactions_AspNetUsers_PerformedById",
                        column: x => x.PerformedById,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StockTransactions_AssetInventories_RelatedInventoryId",
                        column: x => x.RelatedInventoryId,
                        principalTable: "AssetInventories",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_StockTransactions_Assets_AssetId",
                        column: x => x.AssetId,
                        principalTable: "Assets",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_StockTransactions_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "SystemAnnouncements",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Title = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Content = table.Column<string>(type: "text", nullable: false),
                    Kind = table.Column<int>(type: "integer", nullable: false),
                    Severity = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    Channels = table.Column<int>(type: "integer", nullable: false),
                    AudienceJson = table.Column<string>(type: "jsonb", nullable: false, defaultValue: "{}"),
                    ScheduleAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    ExpiresAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    RequireAck = table.Column<bool>(type: "boolean", nullable: false),
                    AllowDismiss = table.Column<bool>(type: "boolean", nullable: false),
                    ImageUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    ActionUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    ActionLabel = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    RecipientCount = table.Column<int>(type: "integer", nullable: false),
                    DeliveredCount = table.Column<int>(type: "integer", nullable: false),
                    SeenCount = table.Column<int>(type: "integer", nullable: false),
                    ClickedCount = table.Column<int>(type: "integer", nullable: false),
                    AckedCount = table.Column<int>(type: "integer", nullable: false),
                    SentAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_SystemAnnouncements", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "UserDeviceTokens",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Token = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    Platform = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    DeviceName = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    AppVersion = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: true),
                    LastUsedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    IsDisabled = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UserDeviceTokens", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "FeedbackReplies",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FeedbackId = table.Column<Guid>(type: "uuid", nullable: false),
                    SenderEmployeeId = table.Column<Guid>(type: "uuid", nullable: true),
                    Content = table.Column<string>(type: "character varying(5000)", maxLength: 5000, nullable: false),
                    ImageUrls = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    IsFromSender = table.Column<bool>(type: "boolean", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FeedbackReplies", x => x.Id);
                    table.ForeignKey(
                        name: "FK_FeedbackReplies_Employees_SenderEmployeeId",
                        column: x => x.SenderEmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_FeedbackReplies_Feedbacks_FeedbackId",
                        column: x => x.FeedbackId,
                        principalTable: "Feedbacks",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_FeedbackReplies_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "FieldLocationAssignments",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    LocationId = table.Column<Guid>(type: "uuid", nullable: false),
                    DayOfWeek = table.Column<int>(type: "integer", nullable: true),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    Note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
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
                    table.PrimaryKey("PK_FieldLocationAssignments", x => x.Id);
                    table.ForeignKey(
                        name: "FK_FieldLocationAssignments_FieldLocations_LocationId",
                        column: x => x.LocationId,
                        principalTable: "FieldLocations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_FieldLocationAssignments_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "VisitReports",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    LocationId = table.Column<Guid>(type: "uuid", nullable: false),
                    LocationName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    VisitDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    CheckInTime = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    CheckOutTime = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    TimeSpentMinutes = table.Column<int>(type: "integer", nullable: true),
                    CheckInLatitude = table.Column<double>(type: "double precision", nullable: true),
                    CheckInLongitude = table.Column<double>(type: "double precision", nullable: true),
                    CheckInDistance = table.Column<double>(type: "double precision", nullable: true),
                    CheckOutLatitude = table.Column<double>(type: "double precision", nullable: true),
                    CheckOutLongitude = table.Column<double>(type: "double precision", nullable: true),
                    CheckOutDistance = table.Column<double>(type: "double precision", nullable: true),
                    PhotoUrlsJson = table.Column<string>(type: "text", nullable: true),
                    ReportNote = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    ReportDataJson = table.Column<string>(type: "text", nullable: true),
                    JourneyId = table.Column<Guid>(type: "uuid", nullable: true),
                    OutsideRadius = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    Status = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    ReviewedBy = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ReviewedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    ReviewNote = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
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
                    table.PrimaryKey("PK_VisitReports", x => x.Id);
                    table.ForeignKey(
                        name: "FK_VisitReports_FieldLocations_LocationId",
                        column: x => x.LocationId,
                        principalTable: "FieldLocations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_VisitReports_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "MealDebts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Type = table.Column<int>(type: "integer", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric", nullable: false),
                    Date = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    MealSessionId = table.Column<Guid>(type: "uuid", nullable: true),
                    Period = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: true),
                    Note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    RecordedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    RecordedByName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
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
                    table.PrimaryKey("PK_MealDebts", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MealDebts_AspNetUsers_EmployeeUserId",
                        column: x => x.EmployeeUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_MealDebts_MealSessions_MealSessionId",
                        column: x => x.MealSessionId,
                        principalTable: "MealSessions",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_MealDebts_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "MealMenus",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Date = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    DayOfWeek = table.Column<int>(type: "integer", nullable: false),
                    MealSessionId = table.Column<Guid>(type: "uuid", nullable: false),
                    Note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
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
                    table.PrimaryKey("PK_MealMenus", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MealMenus_MealSessions_MealSessionId",
                        column: x => x.MealSessionId,
                        principalTable: "MealSessions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_MealMenus_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "MealRecords",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    AttendanceId = table.Column<Guid>(type: "uuid", nullable: true),
                    EmployeeUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    PIN = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    MealSessionId = table.Column<Guid>(type: "uuid", nullable: false),
                    MealTime = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    Date = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    ShiftId = table.Column<Guid>(type: "uuid", nullable: true),
                    DeviceId = table.Column<Guid>(type: "uuid", nullable: true),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MealRecords", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MealRecords_AspNetUsers_EmployeeUserId",
                        column: x => x.EmployeeUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_MealRecords_AttendanceLogs_AttendanceId",
                        column: x => x.AttendanceId,
                        principalTable: "AttendanceLogs",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_MealRecords_Devices_DeviceId",
                        column: x => x.DeviceId,
                        principalTable: "Devices",
                        principalColumn: "Id");
                    table.ForeignKey(
                        name: "FK_MealRecords_MealSessions_MealSessionId",
                        column: x => x.MealSessionId,
                        principalTable: "MealSessions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_MealRecords_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "MealRegistrations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    MealSessionId = table.Column<Guid>(type: "uuid", nullable: false),
                    Date = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    IsRegistered = table.Column<bool>(type: "boolean", nullable: false),
                    RegisteredAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    CancelledAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    Note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MealRegistrations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MealRegistrations_AspNetUsers_EmployeeUserId",
                        column: x => x.EmployeeUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_MealRegistrations_MealSessions_MealSessionId",
                        column: x => x.MealSessionId,
                        principalTable: "MealSessions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_MealRegistrations_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "MealSessionShifts",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    MealSessionId = table.Column<Guid>(type: "uuid", nullable: false),
                    ShiftTemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MealSessionShifts", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MealSessionShifts_MealSessions_MealSessionId",
                        column: x => x.MealSessionId,
                        principalTable: "MealSessions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_MealSessionShifts_ShiftTemplates_ShiftTemplateId",
                        column: x => x.ShiftTemplateId,
                        principalTable: "ShiftTemplates",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "MarketingCampaigns",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    TemplateId = table.Column<Guid>(type: "uuid", nullable: true),
                    AudienceJson = table.Column<string>(type: "jsonb", nullable: false, defaultValue: "{}"),
                    Channels = table.Column<int>(type: "integer", nullable: false),
                    ScheduleAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    AnnouncementId = table.Column<Guid>(type: "uuid", nullable: true),
                    RecipientCount = table.Column<int>(type: "integer", nullable: false),
                    DeliveredCount = table.Column<int>(type: "integer", nullable: false),
                    OpenedCount = table.Column<int>(type: "integer", nullable: false),
                    ClickedCount = table.Column<int>(type: "integer", nullable: false),
                    CreatedByUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    LaunchedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MarketingCampaigns", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MarketingCampaigns_NotificationTemplates_TemplateId",
                        column: x => x.TemplateId,
                        principalTable: "NotificationTemplates",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "ProductItems",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Unit = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    Description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    ProductGroupId = table.Column<Guid>(type: "uuid", nullable: false),
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
                    table.PrimaryKey("PK_ProductItems", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ProductItems_ProductGroups_ProductGroupId",
                        column: x => x.ProductGroupId,
                        principalTable: "ProductGroups",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ProductItems_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "AnnouncementDeliveries",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    AnnouncementId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    Channel = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    DeliveredAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    SeenAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    ClickedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    AckedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    DismissedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AnnouncementDeliveries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AnnouncementDeliveries_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_AnnouncementDeliveries_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_AnnouncementDeliveries_SystemAnnouncements_AnnouncementId",
                        column: x => x.AnnouncementId,
                        principalTable: "SystemAnnouncements",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "MealMenuItems",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    MealMenuId = table.Column<Guid>(type: "uuid", nullable: false),
                    DishName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    Category = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_MealMenuItems", x => x.Id);
                    table.ForeignKey(
                        name: "FK_MealMenuItems_MealMenus_MealMenuId",
                        column: x => x.MealMenuId,
                        principalTable: "MealMenus",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ProductionEntries",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProductItemId = table.Column<Guid>(type: "uuid", nullable: false),
                    WorkDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    Quantity = table.Column<decimal>(type: "numeric", nullable: false),
                    UnitPrice = table.Column<decimal>(type: "numeric", nullable: true),
                    Amount = table.Column<decimal>(type: "numeric", nullable: true),
                    Note = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
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
                    table.PrimaryKey("PK_ProductionEntries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ProductionEntries_Employees_EmployeeId",
                        column: x => x.EmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ProductionEntries_ProductItems_ProductItemId",
                        column: x => x.ProductItemId,
                        principalTable: "ProductItems",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ProductionEntries_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.CreateTable(
                name: "ProductPriceTiers",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ProductItemId = table.Column<Guid>(type: "uuid", nullable: false),
                    MinQuantity = table.Column<int>(type: "integer", nullable: false),
                    MaxQuantity = table.Column<int>(type: "integer", nullable: true),
                    UnitPrice = table.Column<decimal>(type: "numeric", nullable: false),
                    TierLevel = table.Column<int>(type: "integer", nullable: false),
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
                    table.PrimaryKey("PK_ProductPriceTiers", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ProductPriceTiers_ProductItems_ProductItemId",
                        column: x => x.ProductItemId,
                        principalTable: "ProductItems",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ProductPriceTiers_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id");
                });

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000001"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 350, DateTimeKind.Local).AddTicks(6054));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000002"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 350, DateTimeKind.Local).AddTicks(6120));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000003"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 350, DateTimeKind.Local).AddTicks(6126));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000004"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 350, DateTimeKind.Local).AddTicks(6128));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000005"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 350, DateTimeKind.Local).AddTicks(6130));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000006"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 350, DateTimeKind.Local).AddTicks(6133));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000007"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 350, DateTimeKind.Local).AddTicks(6135));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000008"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 350, DateTimeKind.Local).AddTicks(6137));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000009"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 350, DateTimeKind.Local).AddTicks(6139));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7449));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7459));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7461));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7463));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7464));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7466));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7467));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7469));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7471));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7473));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7474));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7476));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7478));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7479));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7519));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7521));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7522));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7524));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7525));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111020"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7527));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111021"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7534));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111022"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7557));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111023"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7559));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111024"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7560));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111025"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7562));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111026"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7563));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111027"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7564));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111028"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7566));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111029"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7568));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111030"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7569));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111031"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7570));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111032"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7572));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111033"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7573));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111034"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7575));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111035"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7576));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111036"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7578));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111037"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7579));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111038"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7580));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111039"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7582));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111040"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7583));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111041"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7585));

            migrationBuilder.InsertData(
                table: "Permissions",
                columns: new[] { "Id", "CreatedAt", "CreatedBy", "Description", "DisplayOrder", "Module", "ModuleDisplayName", "UpdatedAt", "UpdatedBy" },
                values: new object[] { new Guid("11111111-1111-1111-1111-111111111042"), new DateTime(2026, 5, 8, 17, 44, 12, 354, DateTimeKind.Local).AddTicks(7587), null, "Quản lý check-in điểm bán, giao điểm, báo cáo tại điểm", 42, "FieldCheckIn", "Check-in điểm bán", null, null });

            migrationBuilder.CreateIndex(
                name: "IX_Employees_StoreId_CompanyEmail",
                table: "Employees",
                columns: new[] { "StoreId", "CompanyEmail" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Employees_StoreId_EmployeeCode",
                table: "Employees",
                columns: new[] { "StoreId", "EmployeeCode" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_AdvanceApprovalRecords_ActualUserId",
                table: "AdvanceApprovalRecords",
                column: "ActualUserId");

            migrationBuilder.CreateIndex(
                name: "IX_AdvanceApprovalRecords_AdvanceRequestId",
                table: "AdvanceApprovalRecords",
                column: "AdvanceRequestId");

            migrationBuilder.CreateIndex(
                name: "IX_AdvanceApprovalRecords_AssignedUserId",
                table: "AdvanceApprovalRecords",
                column: "AssignedUserId");

            migrationBuilder.CreateIndex(
                name: "IX_AnnouncementDeliveries_AnnId",
                table: "AnnouncementDeliveries",
                column: "AnnouncementId");

            migrationBuilder.CreateIndex(
                name: "IX_AnnouncementDeliveries_StoreId",
                table: "AnnouncementDeliveries",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_AnnouncementDeliveries_User_Status",
                table: "AnnouncementDeliveries",
                columns: new[] { "UserId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_AnnouncementDeliveries_UserId",
                table: "AnnouncementDeliveries",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "UX_AnnouncementDeliveries_Ann_User_Channel",
                table: "AnnouncementDeliveries",
                columns: new[] { "AnnouncementId", "UserId", "Channel" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ApprovalRecords_ActualUserId",
                table: "ApprovalRecords",
                column: "ActualUserId");

            migrationBuilder.CreateIndex(
                name: "IX_ApprovalRecords_AssignedUserId",
                table: "ApprovalRecords",
                column: "AssignedUserId");

            migrationBuilder.CreateIndex(
                name: "IX_ApprovalRecords_CorrectionRequestId",
                table: "ApprovalRecords",
                column: "CorrectionRequestId");

            migrationBuilder.CreateIndex(
                name: "IX_AuthorizedMobileDevices_StoreId",
                table: "AuthorizedMobileDevices",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_BranchPermissions_BranchId",
                table: "BranchPermissions",
                column: "BranchId");

            migrationBuilder.CreateIndex(
                name: "IX_BranchPermissions_StoreId",
                table: "BranchPermissions",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_BranchPermissions_UserId",
                table: "BranchPermissions",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_BranchPermissions_UserId_BranchId_StoreId",
                table: "BranchPermissions",
                columns: new[] { "UserId", "BranchId", "StoreId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_DeviceChangeRequests_StoreId",
                table: "DeviceChangeRequests",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_FeedbackReplies_FeedbackId",
                table: "FeedbackReplies",
                column: "FeedbackId");

            migrationBuilder.CreateIndex(
                name: "IX_FeedbackReplies_SenderEmployeeId",
                table: "FeedbackReplies",
                column: "SenderEmployeeId");

            migrationBuilder.CreateIndex(
                name: "IX_FeedbackReplies_StoreId",
                table: "FeedbackReplies",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Feedbacks_RecipientEmployeeId",
                table: "Feedbacks",
                column: "RecipientEmployeeId");

            migrationBuilder.CreateIndex(
                name: "IX_Feedbacks_RespondedByEmployeeId",
                table: "Feedbacks",
                column: "RespondedByEmployeeId");

            migrationBuilder.CreateIndex(
                name: "IX_Feedbacks_SenderEmployeeId",
                table: "Feedbacks",
                column: "SenderEmployeeId");

            migrationBuilder.CreateIndex(
                name: "IX_Feedbacks_StoreId_Status",
                table: "Feedbacks",
                columns: new[] { "StoreId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_FieldLocationAssign_Employee_Location",
                table: "FieldLocationAssignments",
                columns: new[] { "StoreId", "EmployeeId", "LocationId", "DayOfWeek" });

            migrationBuilder.CreateIndex(
                name: "IX_FieldLocationAssignments_LocationId",
                table: "FieldLocationAssignments",
                column: "LocationId");

            migrationBuilder.CreateIndex(
                name: "IX_FieldLocations_StoreId",
                table: "FieldLocations",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Journey_Employee_Date",
                table: "JourneyTrackings",
                columns: new[] { "StoreId", "EmployeeId", "JourneyDate" });

            migrationBuilder.CreateIndex(
                name: "IX_Journey_Status",
                table: "JourneyTrackings",
                columns: new[] { "StoreId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_LeaveApprovalRecords_ActualUserId",
                table: "LeaveApprovalRecords",
                column: "ActualUserId");

            migrationBuilder.CreateIndex(
                name: "IX_LeaveApprovalRecords_AssignedUserId",
                table: "LeaveApprovalRecords",
                column: "AssignedUserId");

            migrationBuilder.CreateIndex(
                name: "IX_LeaveApprovalRecords_LeaveId",
                table: "LeaveApprovalRecords",
                column: "LeaveId");

            migrationBuilder.CreateIndex(
                name: "IX_MaintenanceWindows_Active_Range",
                table: "MaintenanceWindows",
                columns: new[] { "IsActive", "StartAt", "EndAt" });

            migrationBuilder.CreateIndex(
                name: "IX_MarketingCampaigns_ScheduleAt",
                table: "MarketingCampaigns",
                column: "ScheduleAt");

            migrationBuilder.CreateIndex(
                name: "IX_MarketingCampaigns_Status",
                table: "MarketingCampaigns",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_MarketingCampaigns_TemplateId",
                table: "MarketingCampaigns",
                column: "TemplateId");

            migrationBuilder.CreateIndex(
                name: "IX_MealDebts_EmployeeUserId",
                table: "MealDebts",
                column: "EmployeeUserId");

            migrationBuilder.CreateIndex(
                name: "IX_MealDebts_MealSessionId",
                table: "MealDebts",
                column: "MealSessionId");

            migrationBuilder.CreateIndex(
                name: "IX_MealDebts_StoreId",
                table: "MealDebts",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_MealDishes_StoreId",
                table: "MealDishes",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_MealMenuItems_MealMenuId",
                table: "MealMenuItems",
                column: "MealMenuId");

            migrationBuilder.CreateIndex(
                name: "IX_MealMenus_MealSessionId",
                table: "MealMenus",
                column: "MealSessionId");

            migrationBuilder.CreateIndex(
                name: "IX_MealMenus_StoreId",
                table: "MealMenus",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_MealRecords_AttendanceId",
                table: "MealRecords",
                column: "AttendanceId");

            migrationBuilder.CreateIndex(
                name: "IX_MealRecords_DeviceId",
                table: "MealRecords",
                column: "DeviceId");

            migrationBuilder.CreateIndex(
                name: "IX_MealRecords_EmployeeUserId",
                table: "MealRecords",
                column: "EmployeeUserId");

            migrationBuilder.CreateIndex(
                name: "IX_MealRecords_MealSessionId",
                table: "MealRecords",
                column: "MealSessionId");

            migrationBuilder.CreateIndex(
                name: "IX_MealRecords_StoreId",
                table: "MealRecords",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_MealRegistrations_EmployeeUserId",
                table: "MealRegistrations",
                column: "EmployeeUserId");

            migrationBuilder.CreateIndex(
                name: "IX_MealRegistrations_MealSessionId",
                table: "MealRegistrations",
                column: "MealSessionId");

            migrationBuilder.CreateIndex(
                name: "IX_MealRegistrations_StoreId",
                table: "MealRegistrations",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_MealSessions_StoreId",
                table: "MealSessions",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_MealSessionShifts_MealSessionId",
                table: "MealSessionShifts",
                column: "MealSessionId");

            migrationBuilder.CreateIndex(
                name: "IX_MealSessionShifts_ShiftTemplateId",
                table: "MealSessionShifts",
                column: "ShiftTemplateId");

            migrationBuilder.CreateIndex(
                name: "IX_MobileAttendanceRecords_StoreId",
                table: "MobileAttendanceRecords",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_MobileAttendanceSettings_StoreId",
                table: "MobileAttendanceSettings",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_MobileFaceRegistrations_StoreId",
                table: "MobileFaceRegistrations",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_MobileWorkLocations_StoreId",
                table: "MobileWorkLocations",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "UX_NotificationTemplates_Code",
                table: "NotificationTemplates",
                column: "Code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ProductGroups_StoreId",
                table: "ProductGroups",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_ProductionEntries_EmployeeId",
                table: "ProductionEntries",
                column: "EmployeeId");

            migrationBuilder.CreateIndex(
                name: "IX_ProductionEntries_ProductItemId",
                table: "ProductionEntries",
                column: "ProductItemId");

            migrationBuilder.CreateIndex(
                name: "IX_ProductionEntries_StoreId",
                table: "ProductionEntries",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_ProductItems_ProductGroupId",
                table: "ProductItems",
                column: "ProductGroupId");

            migrationBuilder.CreateIndex(
                name: "IX_ProductItems_StoreId",
                table: "ProductItems",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_ProductPriceTiers_ProductItemId",
                table: "ProductPriceTiers",
                column: "ProductItemId");

            migrationBuilder.CreateIndex(
                name: "IX_ProductPriceTiers_StoreId",
                table: "ProductPriceTiers",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_ShiftStaffingQuotas_ShiftTemplateId",
                table: "ShiftStaffingQuotas",
                column: "ShiftTemplateId");

            migrationBuilder.CreateIndex(
                name: "IX_ShiftStaffingQuotas_StoreId",
                table: "ShiftStaffingQuotas",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_StockTransactions_AssetId",
                table: "StockTransactions",
                column: "AssetId");

            migrationBuilder.CreateIndex(
                name: "IX_StockTransactions_PerformedById",
                table: "StockTransactions",
                column: "PerformedById");

            migrationBuilder.CreateIndex(
                name: "IX_StockTransactions_RelatedInventoryId",
                table: "StockTransactions",
                column: "RelatedInventoryId");

            migrationBuilder.CreateIndex(
                name: "IX_StockTransactions_StoreId",
                table: "StockTransactions",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_SystemAnnouncements_ExpiresAt",
                table: "SystemAnnouncements",
                column: "ExpiresAt");

            migrationBuilder.CreateIndex(
                name: "IX_SystemAnnouncements_ScheduleAt",
                table: "SystemAnnouncements",
                column: "ScheduleAt");

            migrationBuilder.CreateIndex(
                name: "IX_SystemAnnouncements_Status",
                table: "SystemAnnouncements",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_SystemAnnouncements_Status_Expires",
                table: "SystemAnnouncements",
                columns: new[] { "Status", "ExpiresAt" });

            migrationBuilder.CreateIndex(
                name: "IX_UserDeviceTokens_User_Disabled",
                table: "UserDeviceTokens",
                columns: new[] { "UserId", "IsDisabled" });

            migrationBuilder.CreateIndex(
                name: "IX_UserDeviceTokens_UserId",
                table: "UserDeviceTokens",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "UX_UserDeviceTokens_Token",
                table: "UserDeviceTokens",
                column: "Token",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_VisitReport_Employee_Date",
                table: "VisitReports",
                columns: new[] { "StoreId", "EmployeeId", "VisitDate" });

            migrationBuilder.CreateIndex(
                name: "IX_VisitReport_Journey",
                table: "VisitReports",
                columns: new[] { "StoreId", "JourneyId" });

            migrationBuilder.CreateIndex(
                name: "IX_VisitReport_Location_Date",
                table: "VisitReports",
                columns: new[] { "StoreId", "LocationId", "VisitDate" });

            migrationBuilder.CreateIndex(
                name: "IX_VisitReport_Status",
                table: "VisitReports",
                columns: new[] { "StoreId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_VisitReports_LocationId",
                table: "VisitReports",
                column: "LocationId");

            migrationBuilder.AddForeignKey(
                name: "FK_AssetInventories_Employees_ResponsibleUserId",
                table: "AssetInventories",
                column: "ResponsibleUserId",
                principalTable: "Employees",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_Assets_Employees_CurrentAssigneeId",
                table: "Assets",
                column: "CurrentAssigneeId",
                principalTable: "Employees",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_AssetTransfers_Employees_FromUserId",
                table: "AssetTransfers",
                column: "FromUserId",
                principalTable: "Employees",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_AssetTransfers_Employees_ToUserId",
                table: "AssetTransfers",
                column: "ToUserId",
                principalTable: "Employees",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_ShiftTemplates_AspNetUsers_ManagerId",
                table: "ShiftTemplates",
                column: "ManagerId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_ShiftTemplates_Stores_StoreId",
                table: "ShiftTemplates",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AssetInventories_Employees_ResponsibleUserId",
                table: "AssetInventories");

            migrationBuilder.DropForeignKey(
                name: "FK_Assets_Employees_CurrentAssigneeId",
                table: "Assets");

            migrationBuilder.DropForeignKey(
                name: "FK_AssetTransfers_Employees_FromUserId",
                table: "AssetTransfers");

            migrationBuilder.DropForeignKey(
                name: "FK_AssetTransfers_Employees_ToUserId",
                table: "AssetTransfers");

            migrationBuilder.DropForeignKey(
                name: "FK_ShiftTemplates_AspNetUsers_ManagerId",
                table: "ShiftTemplates");

            migrationBuilder.DropForeignKey(
                name: "FK_ShiftTemplates_Stores_StoreId",
                table: "ShiftTemplates");

            migrationBuilder.DropTable(
                name: "AdvanceApprovalRecords");

            migrationBuilder.DropTable(
                name: "AnnouncementDeliveries");

            migrationBuilder.DropTable(
                name: "AppBugReports");

            migrationBuilder.DropTable(
                name: "AppPages");

            migrationBuilder.DropTable(
                name: "ApprovalRecords");

            migrationBuilder.DropTable(
                name: "AuthorizedMobileDevices");

            migrationBuilder.DropTable(
                name: "BranchPermissions");

            migrationBuilder.DropTable(
                name: "DeviceChangeRequests");

            migrationBuilder.DropTable(
                name: "EmployeeLiveLocations");

            migrationBuilder.DropTable(
                name: "FeedbackReplies");

            migrationBuilder.DropTable(
                name: "FieldLocationAssignments");

            migrationBuilder.DropTable(
                name: "JourneyTrackings");

            migrationBuilder.DropTable(
                name: "LeaveApprovalRecords");

            migrationBuilder.DropTable(
                name: "MaintenanceWindows");

            migrationBuilder.DropTable(
                name: "MarketingCampaigns");

            migrationBuilder.DropTable(
                name: "MealDebts");

            migrationBuilder.DropTable(
                name: "MealDishes");

            migrationBuilder.DropTable(
                name: "MealMenuItems");

            migrationBuilder.DropTable(
                name: "MealRecords");

            migrationBuilder.DropTable(
                name: "MealRegistrations");

            migrationBuilder.DropTable(
                name: "MealSessionShifts");

            migrationBuilder.DropTable(
                name: "MobileAttendanceRecords");

            migrationBuilder.DropTable(
                name: "MobileAttendanceSettings");

            migrationBuilder.DropTable(
                name: "MobileFaceRegistrations");

            migrationBuilder.DropTable(
                name: "MobileWorkLocations");

            migrationBuilder.DropTable(
                name: "ProductionEntries");

            migrationBuilder.DropTable(
                name: "ProductPriceTiers");

            migrationBuilder.DropTable(
                name: "ShiftStaffingQuotas");

            migrationBuilder.DropTable(
                name: "StockTransactions");

            migrationBuilder.DropTable(
                name: "UserDeviceTokens");

            migrationBuilder.DropTable(
                name: "VisitReports");

            migrationBuilder.DropTable(
                name: "SystemAnnouncements");

            migrationBuilder.DropTable(
                name: "Feedbacks");

            migrationBuilder.DropTable(
                name: "NotificationTemplates");

            migrationBuilder.DropTable(
                name: "MealMenus");

            migrationBuilder.DropTable(
                name: "ProductItems");

            migrationBuilder.DropTable(
                name: "FieldLocations");

            migrationBuilder.DropTable(
                name: "MealSessions");

            migrationBuilder.DropTable(
                name: "ProductGroups");

            migrationBuilder.DropIndex(
                name: "IX_Employees_StoreId_CompanyEmail",
                table: "Employees");

            migrationBuilder.DropIndex(
                name: "IX_Employees_StoreId_EmployeeCode",
                table: "Employees");

            migrationBuilder.DeleteData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111042"));

            migrationBuilder.DropColumn(
                name: "CommentType",
                table: "TaskComments");

            migrationBuilder.DropColumn(
                name: "ImageUrls",
                table: "TaskComments");

            migrationBuilder.DropColumn(
                name: "LinkUrls",
                table: "TaskComments");

            migrationBuilder.DropColumn(
                name: "ProgressSnapshot",
                table: "TaskComments");

            migrationBuilder.DropColumn(
                name: "Code",
                table: "ShiftTemplates");

            migrationBuilder.DropColumn(
                name: "EarlyCheckInMinutes",
                table: "ShiftTemplates");

            migrationBuilder.DropColumn(
                name: "EarlyLeaveGraceMinutes",
                table: "ShiftTemplates");

            migrationBuilder.DropColumn(
                name: "LateGraceMinutes",
                table: "ShiftTemplates");

            migrationBuilder.DropColumn(
                name: "OvernightCutoffTime",
                table: "ShiftTemplates");

            migrationBuilder.DropColumn(
                name: "OvertimeMinutesThreshold",
                table: "ShiftTemplates");

            migrationBuilder.DropColumn(
                name: "ShiftType",
                table: "ShiftTemplates");

            migrationBuilder.DropColumn(
                name: "Allowances",
                table: "Payslips");

            migrationBuilder.DropColumn(
                name: "HealthInsurance",
                table: "Payslips");

            migrationBuilder.DropColumn(
                name: "SocialInsurance",
                table: "Payslips");

            migrationBuilder.DropColumn(
                name: "Tax",
                table: "Payslips");

            migrationBuilder.DropColumn(
                name: "UnemploymentInsurance",
                table: "Payslips");

            migrationBuilder.DropColumn(
                name: "CurrentApprovalStep",
                table: "Leaves");

            migrationBuilder.DropColumn(
                name: "TotalApprovalLevels",
                table: "Leaves");

            migrationBuilder.DropColumn(
                name: "DeviceType",
                table: "Devices");

            migrationBuilder.DropColumn(
                name: "MobileAttendanceRecordId",
                table: "AttendanceLogs");

            migrationBuilder.DropColumn(
                name: "CurrentApprovalStep",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropColumn(
                name: "TotalApprovalLevels",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropColumn(
                name: "Color",
                table: "Assets");

            migrationBuilder.DropColumn(
                name: "QrCode",
                table: "Assets");

            migrationBuilder.DropColumn(
                name: "Size",
                table: "Assets");

            migrationBuilder.DropColumn(
                name: "StoredExpectedQuantity",
                table: "AssetInventoryItems");

            migrationBuilder.DropColumn(
                name: "CurrentApprovalStep",
                table: "AdvanceRequests");

            migrationBuilder.DropColumn(
                name: "TotalApprovalLevels",
                table: "AdvanceRequests");

            migrationBuilder.AddColumn<string>(
                name: "PlainTextPassword",
                table: "AspNetUsers",
                type: "text",
                nullable: true);

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(687));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(762));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(767));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(771));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(774));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(776));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(778));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(780));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(782));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9584));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9611));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9614));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9615));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9617));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9619));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9621));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9623));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9625));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9627));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9629));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9630));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9632));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9633));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9635));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9636));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9638));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9639));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9641));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111020"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9643));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111021"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9661));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111022"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9686));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111023"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9688));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111024"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9690));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111025"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9692));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111026"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9767));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111027"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9769));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111028"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9771));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111029"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9773));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111030"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9777));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111031"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9779));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111032"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9781));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111033"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9782));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111034"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9784));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111035"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9786));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111036"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9787));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111037"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9789));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111038"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9790));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111039"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9792));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111040"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9793));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111041"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9794));

            migrationBuilder.CreateIndex(
                name: "IX_Employees_CompanyEmail",
                table: "Employees",
                column: "CompanyEmail",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Employees_EmployeeCode",
                table: "Employees",
                column: "EmployeeCode",
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_AssetInventories_AspNetUsers_ResponsibleUserId",
                table: "AssetInventories",
                column: "ResponsibleUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_Assets_AspNetUsers_CurrentAssigneeId",
                table: "Assets",
                column: "CurrentAssigneeId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_AssetTransfers_AspNetUsers_FromUserId",
                table: "AssetTransfers",
                column: "FromUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_AssetTransfers_AspNetUsers_ToUserId",
                table: "AssetTransfers",
                column: "ToUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_ShiftTemplates_AspNetUsers_ManagerId",
                table: "ShiftTemplates",
                column: "ManagerId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_ShiftTemplates_Stores_StoreId",
                table: "ShiftTemplates",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");
        }
    }
}
