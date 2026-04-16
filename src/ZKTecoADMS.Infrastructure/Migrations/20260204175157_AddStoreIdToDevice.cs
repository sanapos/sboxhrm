using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddStoreIdToDevice : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "StoreId1",
                table: "Devices",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Devices_StoreId1",
                table: "Devices",
                column: "StoreId1");

            migrationBuilder.AddForeignKey(
                name: "FK_Devices_Stores_StoreId1",
                table: "Devices",
                column: "StoreId1",
                principalTable: "Stores",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Devices_Stores_StoreId1",
                table: "Devices");

            migrationBuilder.DropIndex(
                name: "IX_Devices_StoreId1",
                table: "Devices");

            migrationBuilder.DropColumn(
                name: "StoreId1",
                table: "Devices");
        }
    }
}
