using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class RenameEmployeeUserIdToEmployeeId : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ScheduleRegistrations_AspNetUsers_EmployeeUserId",
                table: "ScheduleRegistrations");

            migrationBuilder.DropForeignKey(
                name: "FK_WorkSchedules_AspNetUsers_EmployeeUserId",
                table: "WorkSchedules");

            migrationBuilder.RenameColumn(
                name: "EmployeeUserId",
                table: "WorkSchedules",
                newName: "EmployeeId");

            migrationBuilder.RenameIndex(
                name: "IX_WorkSchedules_EmployeeUserId",
                table: "WorkSchedules",
                newName: "IX_WorkSchedules_EmployeeId");

            migrationBuilder.RenameColumn(
                name: "EmployeeUserId",
                table: "ScheduleRegistrations",
                newName: "EmployeeId");

            migrationBuilder.RenameIndex(
                name: "IX_ScheduleRegistrations_EmployeeUserId",
                table: "ScheduleRegistrations",
                newName: "IX_ScheduleRegistrations_EmployeeId");

            // Clean up any existing records whose EmployeeId (formerly EmployeeUserId)
            // does not match an Employee.Id (since FK target changed from AspNetUsers to Employees)
            migrationBuilder.Sql(
                @"DELETE FROM ""WorkSchedules"" WHERE ""EmployeeId"" NOT IN (SELECT ""Id"" FROM ""Employees"");");
            migrationBuilder.Sql(
                @"DELETE FROM ""ScheduleRegistrations"" WHERE ""EmployeeId"" NOT IN (SELECT ""Id"" FROM ""Employees"");");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3165));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3190));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3192));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3195));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3201));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3205));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3207));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3208));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3210));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3212));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3214));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3225));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3227));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3229));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3230));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3232));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3233));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3235));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 25, 56, 251, DateTimeKind.Local).AddTicks(3236));

            migrationBuilder.AddForeignKey(
                name: "FK_ScheduleRegistrations_Employees_EmployeeId",
                table: "ScheduleRegistrations",
                column: "EmployeeId",
                principalTable: "Employees",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_WorkSchedules_Employees_EmployeeId",
                table: "WorkSchedules",
                column: "EmployeeId",
                principalTable: "Employees",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ScheduleRegistrations_Employees_EmployeeId",
                table: "ScheduleRegistrations");

            migrationBuilder.DropForeignKey(
                name: "FK_WorkSchedules_Employees_EmployeeId",
                table: "WorkSchedules");

            migrationBuilder.RenameColumn(
                name: "EmployeeId",
                table: "WorkSchedules",
                newName: "EmployeeUserId");

            migrationBuilder.RenameIndex(
                name: "IX_WorkSchedules_EmployeeId",
                table: "WorkSchedules",
                newName: "IX_WorkSchedules_EmployeeUserId");

            migrationBuilder.RenameColumn(
                name: "EmployeeId",
                table: "ScheduleRegistrations",
                newName: "EmployeeUserId");

            migrationBuilder.RenameIndex(
                name: "IX_ScheduleRegistrations_EmployeeId",
                table: "ScheduleRegistrations",
                newName: "IX_ScheduleRegistrations_EmployeeUserId");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(350));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(379));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(381));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(383));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(385));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(386));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(388));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(398));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(399));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(401));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(403));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(410));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(412));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(413));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(415));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(416));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(419));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(420));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(422));

            migrationBuilder.AddForeignKey(
                name: "FK_ScheduleRegistrations_AspNetUsers_EmployeeUserId",
                table: "ScheduleRegistrations",
                column: "EmployeeUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_WorkSchedules_AspNetUsers_EmployeeUserId",
                table: "WorkSchedules",
                column: "EmployeeUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
