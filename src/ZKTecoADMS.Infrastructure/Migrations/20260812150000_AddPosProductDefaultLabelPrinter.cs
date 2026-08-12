using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>Tách gán máy in tem khỏi gán máy phiếu bếp/hóa đơn.</summary>
public partial class AddPosProductDefaultLabelPrinter : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<Guid>(
            name: "DefaultLabelPrinterId",
            table: "PosProducts",
            type: "uuid",
            nullable: true);

        migrationBuilder.AddColumn<Guid>(
            name: "DefaultLabelPrinterId",
            table: "PosProductCategories",
            type: "uuid",
            nullable: true);

        migrationBuilder.CreateIndex(
            name: "IX_PosProducts_DefaultLabelPrinterId",
            table: "PosProducts",
            column: "DefaultLabelPrinterId");

        migrationBuilder.CreateIndex(
            name: "IX_PosProductCategories_DefaultLabelPrinterId",
            table: "PosProductCategories",
            column: "DefaultLabelPrinterId");

        migrationBuilder.AddForeignKey(
            name: "FK_PosProducts_PosStorePrinters_DefaultLabelPrinterId",
            table: "PosProducts",
            column: "DefaultLabelPrinterId",
            principalTable: "PosStorePrinters",
            principalColumn: "Id",
            onDelete: ReferentialAction.SetNull);

        migrationBuilder.AddForeignKey(
            name: "FK_PosProductCategories_PosStorePrinters_DefaultLabelPrinterId",
            table: "PosProductCategories",
            column: "DefaultLabelPrinterId",
            principalTable: "PosStorePrinters",
            principalColumn: "Id",
            onDelete: ReferentialAction.SetNull);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropForeignKey(
            name: "FK_PosProducts_PosStorePrinters_DefaultLabelPrinterId",
            table: "PosProducts");

        migrationBuilder.DropForeignKey(
            name: "FK_PosProductCategories_PosStorePrinters_DefaultLabelPrinterId",
            table: "PosProductCategories");

        migrationBuilder.DropIndex(
            name: "IX_PosProducts_DefaultLabelPrinterId",
            table: "PosProducts");

        migrationBuilder.DropIndex(
            name: "IX_PosProductCategories_DefaultLabelPrinterId",
            table: "PosProductCategories");

        migrationBuilder.DropColumn(
            name: "DefaultLabelPrinterId",
            table: "PosProducts");

        migrationBuilder.DropColumn(
            name: "DefaultLabelPrinterId",
            table: "PosProductCategories");
    }
}
