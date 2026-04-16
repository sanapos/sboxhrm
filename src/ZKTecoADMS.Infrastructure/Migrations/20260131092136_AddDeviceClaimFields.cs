using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddDeviceClaimFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Employees_SalaryProfiles_BenefitId",
                table: "Employees");

            migrationBuilder.DropIndex(
                name: "IX_Employees_BenefitId",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "BenefitId",
                table: "Employees");

            migrationBuilder.AddColumn<DateTime>(
                name: "ClaimedAt",
                table: "Devices",
                type: "timestamp without time zone",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "IsClaimed",
                table: "Devices",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<Guid>(
                name: "OwnerId",
                table: "Devices",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_SalaryProfiles_Name",
                table: "SalaryProfiles",
                column: "Name");

            migrationBuilder.CreateIndex(
                name: "IX_Devices_OwnerId",
                table: "Devices",
                column: "OwnerId");

            migrationBuilder.AddForeignKey(
                name: "FK_Devices_AspNetUsers_OwnerId",
                table: "Devices",
                column: "OwnerId",
                principalTable: "AspNetUsers",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Devices_AspNetUsers_OwnerId",
                table: "Devices");

            migrationBuilder.DropIndex(
                name: "IX_SalaryProfiles_Name",
                table: "SalaryProfiles");

            migrationBuilder.DropIndex(
                name: "IX_Devices_OwnerId",
                table: "Devices");

            migrationBuilder.DropColumn(
                name: "ClaimedAt",
                table: "Devices");

            migrationBuilder.DropColumn(
                name: "IsClaimed",
                table: "Devices");

            migrationBuilder.DropColumn(
                name: "OwnerId",
                table: "Devices");

            migrationBuilder.AddColumn<Guid>(
                name: "BenefitId",
                table: "Employees",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Employees_BenefitId",
                table: "Employees",
                column: "BenefitId");

            migrationBuilder.AddForeignKey(
                name: "FK_Employees_SalaryProfiles_BenefitId",
                table: "Employees",
                column: "BenefitId",
                principalTable: "SalaryProfiles",
                principalColumn: "Id");
        }
    }
}
