using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>Lưu vị trí chấm công NV chọn khi yêu cầu đổi máy.</summary>
public partial class AddDeviceChangeRequestLocations : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(
            name: "SelectedLocationIdsJson",
            table: "DeviceChangeRequests",
            type: "character varying(4000)",
            maxLength: 4000,
            nullable: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "SelectedLocationIdsJson",
            table: "DeviceChangeRequests");
    }
}
