using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>Nhớ từng báo giá có chèn ảnh sản phẩm khi in lại.</summary>
public partial class AddPosQuoteIncludeImages : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<bool>(
            name: "IncludeImages",
            table: "PosQuotes",
            type: "boolean",
            nullable: false,
            defaultValue: false);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "IncludeImages",
            table: "PosQuotes");
    }
}
