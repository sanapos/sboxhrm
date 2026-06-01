using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <inheritdoc />
public partial class ShiftSwapFkToShiftTemplate : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropForeignKey(
            name: "FK_ShiftSwapRequests_Shifts_RequesterShiftId",
            table: "ShiftSwapRequests");

        migrationBuilder.DropForeignKey(
            name: "FK_ShiftSwapRequests_Shifts_TargetShiftId",
            table: "ShiftSwapRequests");

        migrationBuilder.AddForeignKey(
            name: "FK_ShiftSwapRequests_ShiftTemplates_RequesterShiftId",
            table: "ShiftSwapRequests",
            column: "RequesterShiftId",
            principalTable: "ShiftTemplates",
            principalColumn: "Id",
            onDelete: ReferentialAction.Restrict);

        migrationBuilder.AddForeignKey(
            name: "FK_ShiftSwapRequests_ShiftTemplates_TargetShiftId",
            table: "ShiftSwapRequests",
            column: "TargetShiftId",
            principalTable: "ShiftTemplates",
            principalColumn: "Id",
            onDelete: ReferentialAction.Restrict);
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropForeignKey(
            name: "FK_ShiftSwapRequests_ShiftTemplates_RequesterShiftId",
            table: "ShiftSwapRequests");

        migrationBuilder.DropForeignKey(
            name: "FK_ShiftSwapRequests_ShiftTemplates_TargetShiftId",
            table: "ShiftSwapRequests");

        migrationBuilder.AddForeignKey(
            name: "FK_ShiftSwapRequests_Shifts_RequesterShiftId",
            table: "ShiftSwapRequests",
            column: "RequesterShiftId",
            principalTable: "Shifts",
            principalColumn: "Id",
            onDelete: ReferentialAction.Restrict);

        migrationBuilder.AddForeignKey(
            name: "FK_ShiftSwapRequests_Shifts_TargetShiftId",
            table: "ShiftSwapRequests",
            column: "TargetShiftId",
            principalTable: "Shifts",
            principalColumn: "Id",
            onDelete: ReferentialAction.Restrict);
    }
}
