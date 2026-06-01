using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

public partial class AddNewPunchTypeToAttendanceCorrection : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(
            @"ALTER TABLE ""AttendanceCorrectionRequests"" ADD COLUMN IF NOT EXISTS ""NewPunchType"" character varying(20) NULL;");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(
            @"ALTER TABLE ""AttendanceCorrectionRequests"" DROP COLUMN IF EXISTS ""NewPunchType"";");
    }
}
