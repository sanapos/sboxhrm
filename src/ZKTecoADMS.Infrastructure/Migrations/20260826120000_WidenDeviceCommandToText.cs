using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>
/// DATA UPDATE FINGERTMP/BIODATA embeds the full template; varchar(1000) caused copy 500.
/// </summary>
public partial class WidenDeviceCommandToText : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            ALTER TABLE "DeviceCommands" ALTER COLUMN "Command" TYPE text;
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            ALTER TABLE "DeviceCommands" ALTER COLUMN "Command" TYPE character varying(1000);
            """);
    }
}
