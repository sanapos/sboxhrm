using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>EF model snapshot was missing SitePhotoUrl — uploads saved files but never persisted the path.</summary>
[DbContext(typeof(ZKTecoDbContext))]
[Migration("20260604080000_MapSitePhotoUrlOnMobileAttendanceRecord")]
public partial class MapSitePhotoUrlOnMobileAttendanceRecord : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(
            """
            ALTER TABLE "MobileAttendanceRecords"
            ADD COLUMN IF NOT EXISTS "SitePhotoUrl" character varying(500);
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "SitePhotoUrl",
            table: "MobileAttendanceRecords");
    }
}
