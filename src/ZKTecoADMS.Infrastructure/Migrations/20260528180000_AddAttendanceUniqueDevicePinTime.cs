using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>
/// Remove duplicate attendance rows, then enforce unique (DeviceId, PIN, AttendanceTime).
/// </summary>
public partial class AddAttendanceUniqueDevicePinTime : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql("""
            DELETE FROM "AttendanceLogs" a
            WHERE a."Id" IN (
                SELECT al."Id"
                FROM (
                    SELECT "Id",
                           ROW_NUMBER() OVER (
                               PARTITION BY "DeviceId", "PIN", "AttendanceTime"
                               ORDER BY "CreatedAt" ASC, "Id" ASC
                           ) AS rn
                    FROM "AttendanceLogs"
                ) al
                WHERE al.rn > 1
            );
            """);

        migrationBuilder.Sql("""
            CREATE UNIQUE INDEX IF NOT EXISTS "UX_Attendance_Device_Pin_Time"
            ON "AttendanceLogs" ("DeviceId", "PIN", "AttendanceTime");
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""UX_Attendance_Device_Pin_Time"";");
    }
}
