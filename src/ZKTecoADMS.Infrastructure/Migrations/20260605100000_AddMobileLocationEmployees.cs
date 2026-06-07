using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>Gán nhân viên theo vị trí chấm công mobile + lưu chi nhánh chọn khi đăng ký thiết bị.</summary>
public partial class AddMobileLocationEmployees : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(
            name: "SelectedLocationIdsJson",
            table: "AuthorizedMobileDevices",
            type: "character varying(4000)",
            maxLength: 4000,
            nullable: true);

        migrationBuilder.CreateTable(
            name: "MobileLocationEmployees",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                WorkLocationId = table.Column<Guid>(type: "uuid", nullable: false),
                EmployeeId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                EmployeeName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                IsActive = table.Column<bool>(type: "boolean", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                CreatedBy = table.Column<string>(type: "text", nullable: true),
                UpdatedBy = table.Column<string>(type: "text", nullable: true),
                LastModified = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                LastModifiedBy = table.Column<string>(type: "text", nullable: true),
                Deleted = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                DeletedBy = table.Column<string>(type: "text", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_MobileLocationEmployees", x => x.Id);
                table.ForeignKey(
                    name: "FK_MobileLocationEmployees_MobileWorkLocations_WorkLocationId",
                    column: x => x.WorkLocationId,
                    principalTable: "MobileWorkLocations",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_MobileLocationEmployees_Stores_StoreId",
                    column: x => x.StoreId,
                    principalTable: "Stores",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_MobileLocationEmployees_StoreId_EmployeeId",
            table: "MobileLocationEmployees",
            columns: new[] { "StoreId", "EmployeeId" });

        migrationBuilder.CreateIndex(
            name: "IX_MobileLocationEmployees_StoreId_WorkLocationId_EmployeeId",
            table: "MobileLocationEmployees",
            columns: new[] { "StoreId", "WorkLocationId", "EmployeeId" },
            unique: true,
            filter: "\"Deleted\" IS NULL");

        migrationBuilder.CreateIndex(
            name: "IX_MobileLocationEmployees_WorkLocationId",
            table: "MobileLocationEmployees",
            column: "WorkLocationId");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "MobileLocationEmployees");
        migrationBuilder.DropColumn(
            name: "SelectedLocationIdsJson",
            table: "AuthorizedMobileDevices");
    }
}
