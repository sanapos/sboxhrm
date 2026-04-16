using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class ChangeShiftFkToShiftTemplate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ScheduleRegistrations_Shifts_ShiftId",
                table: "ScheduleRegistrations");

            migrationBuilder.DropForeignKey(
                name: "FK_WorkSchedules_Shifts_ShiftId",
                table: "WorkSchedules");

            // Clean up any existing records whose ShiftId references Shifts (old table) 
            // but not ShiftTemplates (new table)
            migrationBuilder.Sql(
                @"DELETE FROM ""WorkSchedules"" WHERE ""ShiftId"" IS NOT NULL AND ""ShiftId"" NOT IN (SELECT ""Id"" FROM ""ShiftTemplates"");");
            migrationBuilder.Sql(
                @"DELETE FROM ""ScheduleRegistrations"" WHERE ""ShiftId"" IS NOT NULL AND ""ShiftId"" NOT IN (SELECT ""Id"" FROM ""ShiftTemplates"");");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5038));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5063));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5065));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5067));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5068));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5070));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5071));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5078));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5081));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5083));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5084));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5086));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5088));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5089));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5091));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5092));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5094));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5095));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 7, 35, 14, 312, DateTimeKind.Local).AddTicks(5097));

            migrationBuilder.AddForeignKey(
                name: "FK_ScheduleRegistrations_ShiftTemplates_ShiftId",
                table: "ScheduleRegistrations",
                column: "ShiftId",
                principalTable: "ShiftTemplates",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_WorkSchedules_ShiftTemplates_ShiftId",
                table: "WorkSchedules",
                column: "ShiftId",
                principalTable: "ShiftTemplates",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ScheduleRegistrations_ShiftTemplates_ShiftId",
                table: "ScheduleRegistrations");

            migrationBuilder.DropForeignKey(
                name: "FK_WorkSchedules_ShiftTemplates_ShiftId",
                table: "WorkSchedules");

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
                name: "FK_ScheduleRegistrations_Shifts_ShiftId",
                table: "ScheduleRegistrations",
                column: "ShiftId",
                principalTable: "Shifts",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);

            migrationBuilder.AddForeignKey(
                name: "FK_WorkSchedules_Shifts_ShiftId",
                table: "WorkSchedules",
                column: "ShiftId",
                principalTable: "Shifts",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
