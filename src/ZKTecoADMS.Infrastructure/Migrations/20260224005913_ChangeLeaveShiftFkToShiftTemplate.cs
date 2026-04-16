using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class ChangeLeaveShiftFkToShiftTemplate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Leaves_Shifts_ShiftId",
                table: "Leaves");

            migrationBuilder.DropIndex(
                name: "IX_Leaves_ShiftId",
                table: "Leaves");

            migrationBuilder.AlterColumn<Guid>(
                name: "ShiftId",
                table: "Leaves",
                type: "uuid",
                nullable: true,
                oldClrType: typeof(Guid),
                oldType: "uuid");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5648));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5728));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5730));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5735));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5742));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5744));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5745));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5747));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5749));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5751));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5752));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5754));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5756));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5757));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5759));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5761));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5762));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5764));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 24, 7, 59, 11, 825, DateTimeKind.Local).AddTicks(5765));

            migrationBuilder.CreateIndex(
                name: "IX_Leaves_ShiftId",
                table: "Leaves",
                column: "ShiftId");

            migrationBuilder.AddForeignKey(
                name: "FK_Leaves_ShiftTemplates_ShiftId",
                table: "Leaves",
                column: "ShiftId",
                principalTable: "ShiftTemplates",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Leaves_ShiftTemplates_ShiftId",
                table: "Leaves");

            migrationBuilder.DropIndex(
                name: "IX_Leaves_ShiftId",
                table: "Leaves");

            migrationBuilder.AlterColumn<Guid>(
                name: "ShiftId",
                table: "Leaves",
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
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3141));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3168));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3171));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3173));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3175));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3178));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3180));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3182));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3185));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3187));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3189));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3191));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3193));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3195));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3197));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3199));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3202));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3203));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 23, 10, 41, 30, 850, DateTimeKind.Local).AddTicks(3205));

            migrationBuilder.CreateIndex(
                name: "IX_Leaves_ShiftId",
                table: "Leaves",
                column: "ShiftId",
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_Leaves_Shifts_ShiftId",
                table: "Leaves",
                column: "ShiftId",
                principalTable: "Shifts",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
