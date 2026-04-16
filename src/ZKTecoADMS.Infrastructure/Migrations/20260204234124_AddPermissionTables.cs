using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

#pragma warning disable CA1814 // Prefer jagged arrays over multidimensional

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddPermissionTables : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Permissions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Module = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    ModuleDisplayName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Description = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    DisplayOrder = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Permissions", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "RolePermissions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    RoleName = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    RoleDisplayName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    PermissionId = table.Column<Guid>(type: "uuid", nullable: false),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CanView = table.Column<bool>(type: "boolean", nullable: false),
                    CanCreate = table.Column<bool>(type: "boolean", nullable: false),
                    CanEdit = table.Column<bool>(type: "boolean", nullable: false),
                    CanDelete = table.Column<bool>(type: "boolean", nullable: false),
                    CanExport = table.Column<bool>(type: "boolean", nullable: false),
                    CanApprove = table.Column<bool>(type: "boolean", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    CreatedBy = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RolePermissions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_RolePermissions_Permissions_PermissionId",
                        column: x => x.PermissionId,
                        principalTable: "Permissions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_RolePermissions_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.InsertData(
                table: "Permissions",
                columns: new[] { "Id", "CreatedAt", "CreatedBy", "Description", "DisplayOrder", "Module", "ModuleDisplayName", "UpdatedAt", "UpdatedBy" },
                values: new object[,]
                {
                    { new Guid("11111111-1111-1111-1111-111111111001"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9389), null, "Xem tổng quan hệ thống", 1, "Dashboard", "Tổng quan", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111002"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9411), null, "Quản lý thông tin nhân viên", 2, "Employee", "Nhân viên", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111003"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9413), null, "Quản lý chấm công", 3, "Attendance", "Chấm công", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111004"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9415), null, "Quản lý đơn nghỉ phép", 4, "Leave", "Nghỉ phép", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111005"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9421), null, "Quản lý ca làm việc", 5, "Shift", "Ca làm việc", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111006"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9423), null, "Quản lý bảng lương", 6, "Salary", "Lương", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111007"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9425), null, "Quản lý phiếu lương", 7, "Payslip", "Phiếu lương", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111008"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9427), null, "Quản lý thiết bị chấm công", 8, "Device", "Thiết bị", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111009"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9428), null, "Xem và xuất báo cáo", 9, "Report", "Báo cáo", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111010"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9430), null, "Cấu hình hệ thống", 10, "Settings", "Thiết lập", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111011"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9431), null, "Quản lý tài khoản người dùng", 11, "Account", "Tài khoản", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111012"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9433), null, "Quản lý phân quyền", 12, "Role", "Phân quyền", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111013"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9462), null, "Quản lý cửa hàng", 13, "Store", "Cửa hàng", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111014"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9464), null, "Quản lý phụ cấp", 14, "Allowance", "Phụ cấp", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111015"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9466), null, "Quản lý ngày lễ", 15, "Holiday", "Ngày lễ", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111016"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9468), null, "Quản lý bảo hiểm", 16, "Insurance", "Bảo hiểm", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111017"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9470), null, "Quản lý thuế thu nhập", 17, "Tax", "Thuế TNCN", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111018"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9471), null, "Quản lý tạm ứng lương", 18, "Advance", "Tạm ứng", null, null },
                    { new Guid("11111111-1111-1111-1111-111111111019"), new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9473), null, "Quản lý thông báo", 19, "Notification", "Thông báo", null, null }
                });

            migrationBuilder.CreateIndex(
                name: "IX_Permissions_Module",
                table: "Permissions",
                column: "Module",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_RolePermissions_PermissionId",
                table: "RolePermissions",
                column: "PermissionId");

            migrationBuilder.CreateIndex(
                name: "IX_RolePermissions_RoleName_PermissionId_StoreId",
                table: "RolePermissions",
                columns: new[] { "RoleName", "PermissionId", "StoreId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_RolePermissions_StoreId",
                table: "RolePermissions",
                column: "StoreId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "RolePermissions");

            migrationBuilder.DropTable(
                name: "Permissions");
        }
    }
}
