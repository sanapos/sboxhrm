using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class FixAttendanceForeignKeyDeleteBehavior : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckInAttendanceId",
                table: "Shifts");

            migrationBuilder.DropForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckOutAttendanceId",
                table: "Shifts");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9430));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9534));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9538));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9540));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9542));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9544));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9545));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9547));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9549));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9550));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9552));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9554));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9555));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9557));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9559));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9560));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9562));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9563));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 6, 18, 26, 19, 790, DateTimeKind.Local).AddTicks(9565));

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId",
                table: "AttendanceCorrectionRequests",
                column: "AttendanceId",
                principalTable: "AttendanceLogs",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

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

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckInAttendanceId",
                table: "Shifts");

            migrationBuilder.DropForeignKey(
                name: "FK_Shifts_AttendanceLogs_CheckOutAttendanceId",
                table: "Shifts");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(8));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(91));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(93));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(95));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(96));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(98));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(100));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(102));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(103));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(105));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(106));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(108));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(109));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(111));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(112));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(114));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(115));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(117));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 3, 14, 49, 19, 426, DateTimeKind.Local).AddTicks(118));

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_AttendanceLogs_AttendanceId",
                table: "AttendanceCorrectionRequests",
                column: "AttendanceId",
                principalTable: "AttendanceLogs",
                principalColumn: "Id");

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
        }
    }
}
