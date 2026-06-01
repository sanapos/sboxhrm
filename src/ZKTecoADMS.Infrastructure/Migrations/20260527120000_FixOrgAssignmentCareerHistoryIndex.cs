using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <inheritdoc />
public partial class FixOrgAssignmentCareerHistoryIndex : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_OrgAssignments_Emp_Dept_Pos",
            table: "OrgAssignments");

        migrationBuilder.CreateIndex(
            name: "IX_OrgAssignments_Emp_Dept_Pos_Active",
            table: "OrgAssignments",
            columns: new[] { "EmployeeId", "DepartmentId", "PositionId" },
            unique: true,
            filter: "\"Deleted\" IS NULL AND \"EndDate\" IS NULL");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(
            name: "IX_OrgAssignments_Emp_Dept_Pos_Active",
            table: "OrgAssignments");

        migrationBuilder.CreateIndex(
            name: "IX_OrgAssignments_Emp_Dept_Pos",
            table: "OrgAssignments",
            columns: new[] { "EmployeeId", "DepartmentId", "PositionId" },
            unique: true);
    }
}
