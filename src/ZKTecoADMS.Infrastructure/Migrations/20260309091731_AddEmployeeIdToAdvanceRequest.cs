using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddEmployeeIdToAdvanceRequest : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AdvanceRequests_AspNetUsers_EmployeeUserId",
                table: "AdvanceRequests");

            migrationBuilder.AlterColumn<Guid>(
                name: "EmployeeUserId",
                table: "AdvanceRequests",
                type: "uuid",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uuid");

            migrationBuilder.AddColumn<Guid>(
                name: "EmployeeId",
                table: "AdvanceRequests",
                type: "uuid",
                nullable: true);

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8581));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8693));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8695));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8697));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8699));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8702));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8703));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8705));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8707));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8708));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8711));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8714));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8716));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8717));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8720));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8721));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8722));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8724));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 16, 17, 29, 525, DateTimeKind.Local).AddTicks(8728));

            migrationBuilder.CreateIndex(
                name: "IX_AdvanceRequests_EmployeeId",
                table: "AdvanceRequests",
                column: "EmployeeId");

            migrationBuilder.AddForeignKey(
                name: "FK_AdvanceRequests_AspNetUsers_EmployeeUserId",
                table: "AdvanceRequests",
                column: "EmployeeUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_AdvanceRequests_Employees_EmployeeId",
                table: "AdvanceRequests",
                column: "EmployeeId",
                principalTable: "Employees",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AdvanceRequests_AspNetUsers_EmployeeUserId",
                table: "AdvanceRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_AdvanceRequests_Employees_EmployeeId",
                table: "AdvanceRequests");

            migrationBuilder.DropIndex(
                name: "IX_AdvanceRequests_EmployeeId",
                table: "AdvanceRequests");

            migrationBuilder.DropColumn(
                name: "EmployeeId",
                table: "AdvanceRequests");

            migrationBuilder.AlterColumn<Guid>(
                name: "EmployeeUserId",
                table: "AdvanceRequests",
                type: "uuid",
                nullable: false,
                defaultValue: new Guid("00000000-0000-0000-0000-000000000000"),
                oldClrType: typeof(Guid),
                oldType: "uuid",
                oldNullable: true);

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3686));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3710));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3712));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3713));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3715));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3717));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3719));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3720));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3722));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3723));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3725));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3726));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3728));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3729));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3731));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3732));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3734));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3735));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 9, 1, 8, 43, 915, DateTimeKind.Local).AddTicks(3737));

            migrationBuilder.AddForeignKey(
                name: "FK_AdvanceRequests_AspNetUsers_EmployeeUserId",
                table: "AdvanceRequests",
                column: "EmployeeUserId",
                principalTable: "AspNetUsers",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
