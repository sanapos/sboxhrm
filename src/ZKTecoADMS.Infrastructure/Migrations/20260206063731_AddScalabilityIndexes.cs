using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddScalabilityIndexes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameIndex(
                name: "IX_Stores_Code",
                table: "Stores",
                newName: "IX_Store_Code");

            migrationBuilder.RenameIndex(
                name: "IX_Stores_AgentId",
                table: "Stores",
                newName: "IX_Store_AgentId");

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

            migrationBuilder.CreateTable(
                name: "AuditLogs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Action = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EntityType = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    EntityId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    EntityName = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    Details = table.Column<string>(type: "text", nullable: true),
                    UserId = table.Column<Guid>(type: "uuid", nullable: true),
                    UserEmail = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    UserName = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    UserRole = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    StoreName = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    IpAddress = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    UserAgent = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    Timestamp = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    Status = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    ErrorMessage = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AuditLogs", x => x.Id);
                });

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2723));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2792));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2794));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2796));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2797));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2801));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2803));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2805));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2807));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2808));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2810));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2811));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2813));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2815));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2816));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2818));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2819));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2821));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 13, 37, 29, 988, DateTimeKind.Local).AddTicks(2822));

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
                name: "IX_AuditLogs_Action",
                table: "AuditLogs",
                column: "Action");

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_EntityType",
                table: "AuditLogs",
                column: "EntityType");

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_StoreId",
                table: "AuditLogs",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_Timestamp",
                table: "AuditLogs",
                column: "Timestamp");

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_Timestamp_Action",
                table: "AuditLogs",
                columns: new[] { "Timestamp", "Action" });

            migrationBuilder.CreateIndex(
                name: "IX_AuditLogs_UserId",
                table: "AuditLogs",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AuditLogs");

            migrationBuilder.DropIndex(
                name: "IX_Store_ExpiryDate",
                table: "Stores");

            migrationBuilder.DropIndex(
                name: "IX_Store_IsActive",
                table: "Stores");

            migrationBuilder.DropIndex(
                name: "IX_Store_IsActive_IsLocked",
                table: "Stores");

            migrationBuilder.DropIndex(
                name: "IX_Store_IsLocked",
                table: "Stores");

            migrationBuilder.DropIndex(
                name: "IX_Device_DeviceStatus",
                table: "Devices");

            migrationBuilder.DropIndex(
                name: "IX_Device_IsClaimed",
                table: "Devices");

            migrationBuilder.DropIndex(
                name: "IX_Device_LastOnline",
                table: "Devices");

            migrationBuilder.DropIndex(
                name: "IX_Device_StoreId_DeviceStatus",
                table: "Devices");

            migrationBuilder.DropIndex(
                name: "IX_Attendance_AttendanceTime",
                table: "AttendanceLogs");

            migrationBuilder.DropIndex(
                name: "IX_Attendance_DeviceId_AttendanceTime",
                table: "AttendanceLogs");

            migrationBuilder.DropIndex(
                name: "IX_Attendance_EmployeeId_AttendanceTime",
                table: "AttendanceLogs");

            migrationBuilder.RenameIndex(
                name: "IX_Store_Code",
                table: "Stores",
                newName: "IX_Stores_Code");

            migrationBuilder.RenameIndex(
                name: "IX_Store_AgentId",
                table: "Stores",
                newName: "IX_Stores_AgentId");

            migrationBuilder.RenameIndex(
                name: "IX_Device_StoreId",
                table: "Devices",
                newName: "IX_Devices_StoreId");

            migrationBuilder.RenameIndex(
                name: "IX_Device_SerialNumber",
                table: "Devices",
                newName: "IX_Devices_SerialNumber");

            migrationBuilder.RenameIndex(
                name: "IX_Attendance_PIN",
                table: "AttendanceLogs",
                newName: "IX_AttendanceLogs_PIN");

            migrationBuilder.RenameIndex(
                name: "IX_Attendance_EmployeeId",
                table: "AttendanceLogs",
                newName: "IX_AttendanceLogs_EmployeeId");

            migrationBuilder.RenameIndex(
                name: "IX_Attendance_DeviceId",
                table: "AttendanceLogs",
                newName: "IX_AttendanceLogs_DeviceId");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3018));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3051));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3053));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3055));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3056));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3058));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3060));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3064));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3066));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3067));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3069));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3071));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3072));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3074));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3077));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3078));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3080));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3081));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 6, 12, 56, 38, 493, DateTimeKind.Local).AddTicks(3083));
        }
    }
}
