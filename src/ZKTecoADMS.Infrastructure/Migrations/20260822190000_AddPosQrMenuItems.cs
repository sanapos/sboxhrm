using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>Menu riêng QR bàn / đặt online với giá tuỳ chỉnh.</summary>
public partial class AddPosQrMenuItems : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "PosQrMenuItems",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                ProductId = table.Column<Guid>(type: "uuid", nullable: false),
                ShowOnTable = table.Column<bool>(type: "boolean", nullable: false),
                ShowOnOnline = table.Column<bool>(type: "boolean", nullable: false),
                QrPrice = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: true),
                SortOrder = table.Column<int>(type: "integer", nullable: false),
                IsActive = table.Column<bool>(type: "boolean", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                CreatedBy = table.Column<string>(type: "text", nullable: true),
                UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                UpdatedBy = table.Column<string>(type: "text", nullable: true),
                Deleted = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                DeletedBy = table.Column<string>(type: "text", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_PosQrMenuItems", x => x.Id);
                table.ForeignKey(
                    name: "FK_PosQrMenuItems_PosProducts_ProductId",
                    column: x => x.ProductId,
                    principalTable: "PosProducts",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_PosQrMenuItems_Stores_StoreId",
                    column: x => x.StoreId,
                    principalTable: "Stores",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_PosQrMenuItems_StoreId_ProductId",
            table: "PosQrMenuItems",
            columns: new[] { "StoreId", "ProductId" },
            unique: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "PosQrMenuItems");
    }
}
