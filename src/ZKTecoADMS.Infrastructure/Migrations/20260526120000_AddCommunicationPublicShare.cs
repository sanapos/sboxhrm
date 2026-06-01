using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddCommunicationPublicShare : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<bool>(
            name: "IsPublicShareEnabled",
            table: "InternalCommunications",
            type: "boolean",
            nullable: false,
            defaultValue: false);

        migrationBuilder.AddColumn<string>(
            name: "PublicShareToken",
            table: "InternalCommunications",
            type: "character varying(64)",
            maxLength: 64,
            nullable: true);

        migrationBuilder.CreateIndex(
            name: "IX_InternalCommunications_PublicShareToken",
            table: "InternalCommunications",
            column: "PublicShareToken",
            unique: true,
            filter: "\"PublicShareToken\" IS NOT NULL");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_InternalCommunications_PublicShareToken",
            table: "InternalCommunications");

        migrationBuilder.DropColumn(
            name: "IsPublicShareEnabled",
            table: "InternalCommunications");

        migrationBuilder.DropColumn(
            name: "PublicShareToken",
            table: "InternalCommunications");
    }
}
