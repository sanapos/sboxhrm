using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>
/// Restores per-shift unique index (Employee + Date + Shift) so multiple shifts per day are allowed.
/// </summary>
public partial class RestoreWorkScheduleMultiShiftIndex : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_WorkSchedules_Employee_Date"";");
        migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_WorkSchedules_Employee_Date_Shift"";");
        migrationBuilder.Sql(@"
            CREATE UNIQUE INDEX ""IX_WorkSchedules_Employee_Date_Shift""
            ON ""WorkSchedules"" (""EmployeeId"", ""Date"", ""ShiftId"");
        ");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_WorkSchedules_Employee_Date_Shift"";");
        migrationBuilder.Sql(@"
            CREATE UNIQUE INDEX ""IX_WorkSchedules_Employee_Date""
            ON ""WorkSchedules"" (""EmployeeId"", ""Date"");
        ");
    }
}
