using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

public partial class EnhanceTaskAssignment : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<Guid>(
            name: "BranchId",
            table: "WorkTasks",
            type: "uuid",
            nullable: true);

        migrationBuilder.AddColumn<Guid>(
            name: "DepartmentId",
            table: "WorkTasks",
            type: "uuid",
            nullable: true);

        migrationBuilder.AddColumn<Guid>(
            name: "TemplateId",
            table: "WorkTasks",
            type: "uuid",
            nullable: true);

        migrationBuilder.AddColumn<int>(
            name: "SlaReminderHours",
            table: "WorkTasks",
            type: "integer",
            nullable: true);

        migrationBuilder.AddColumn<DateTime>(
            name: "AcceptedAt",
            table: "WorkTasks",
            type: "timestamp without time zone",
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "RejectionReason",
            table: "WorkTasks",
            type: "character varying(500)",
            maxLength: 500,
            nullable: true);

        migrationBuilder.AddColumn<string>(
            name: "AssignmentNote",
            table: "WorkTasks",
            type: "character varying(1000)",
            maxLength: 1000,
            nullable: true);

        migrationBuilder.CreateTable(
            name: "TaskTemplates",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                StoreId = table.Column<Guid>(type: "uuid", nullable: false),
                Name = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                Title = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                Description = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: true),
                TaskType = table.Column<int>(type: "integer", nullable: false),
                Priority = table.Column<int>(type: "integer", nullable: false),
                EstimatedHours = table.Column<decimal>(type: "numeric", nullable: true),
                DefaultSlaReminderHours = table.Column<int>(type: "integer", nullable: true),
                Tags = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                Checklist = table.Column<string>(type: "character varying(4000)", maxLength: 4000, nullable: true),
                IsActive = table.Column<bool>(type: "boolean", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                CreatedBy = table.Column<string>(type: "text", nullable: true),
                UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                UpdatedBy = table.Column<string>(type: "text", nullable: true),
                Deleted = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                DeletedBy = table.Column<string>(type: "text", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_TaskTemplates", x => x.Id);
                table.ForeignKey(
                    name: "FK_TaskTemplates_Stores_StoreId",
                    column: x => x.StoreId,
                    principalTable: "Stores",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateTable(
            name: "TaskDependencies",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                TaskId = table.Column<Guid>(type: "uuid", nullable: false),
                DependsOnTaskId = table.Column<Guid>(type: "uuid", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_TaskDependencies", x => x.Id);
                table.ForeignKey(
                    name: "FK_TaskDependencies_WorkTasks_DependsOnTaskId",
                    column: x => x.DependsOnTaskId,
                    principalTable: "WorkTasks",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Restrict);
                table.ForeignKey(
                    name: "FK_TaskDependencies_WorkTasks_TaskId",
                    column: x => x.TaskId,
                    principalTable: "WorkTasks",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_WorkTasks_BranchId",
            table: "WorkTasks",
            column: "BranchId");

        migrationBuilder.CreateIndex(
            name: "IX_WorkTasks_DepartmentId",
            table: "WorkTasks",
            column: "DepartmentId");

        migrationBuilder.CreateIndex(
            name: "IX_WorkTasks_TemplateId",
            table: "WorkTasks",
            column: "TemplateId");

        migrationBuilder.CreateIndex(
            name: "IX_TaskTemplates_StoreId",
            table: "TaskTemplates",
            column: "StoreId");

        migrationBuilder.CreateIndex(
            name: "IX_TaskDependencies_TaskId_DependsOnTaskId",
            table: "TaskDependencies",
            columns: new[] { "TaskId", "DependsOnTaskId" },
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_TaskDependencies_DependsOnTaskId",
            table: "TaskDependencies",
            column: "DependsOnTaskId");

        migrationBuilder.AddForeignKey(
            name: "FK_WorkTasks_Branches_BranchId",
            table: "WorkTasks",
            column: "BranchId",
            principalTable: "Branches",
            principalColumn: "Id",
            onDelete: ReferentialAction.SetNull);

        migrationBuilder.AddForeignKey(
            name: "FK_WorkTasks_Departments_DepartmentId",
            table: "WorkTasks",
            column: "DepartmentId",
            principalTable: "Departments",
            principalColumn: "Id",
            onDelete: ReferentialAction.SetNull);

        migrationBuilder.AddForeignKey(
            name: "FK_WorkTasks_TaskTemplates_TemplateId",
            table: "WorkTasks",
            column: "TemplateId",
            principalTable: "TaskTemplates",
            principalColumn: "Id",
            onDelete: ReferentialAction.SetNull);

        migrationBuilder.AlterColumn<string>(
            name: "TaskCode",
            table: "WorkTasks",
            type: "character varying(32)",
            maxLength: 32,
            nullable: false,
            oldClrType: typeof(string),
            oldType: "character varying(20)",
            oldMaxLength: 20);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropForeignKey(name: "FK_WorkTasks_Branches_BranchId", table: "WorkTasks");
        migrationBuilder.DropForeignKey(name: "FK_WorkTasks_Departments_DepartmentId", table: "WorkTasks");
        migrationBuilder.DropForeignKey(name: "FK_WorkTasks_TaskTemplates_TemplateId", table: "WorkTasks");
        migrationBuilder.DropTable(name: "TaskDependencies");
        migrationBuilder.DropTable(name: "TaskTemplates");
        migrationBuilder.DropIndex(name: "IX_WorkTasks_BranchId", table: "WorkTasks");
        migrationBuilder.DropIndex(name: "IX_WorkTasks_DepartmentId", table: "WorkTasks");
        migrationBuilder.DropIndex(name: "IX_WorkTasks_TemplateId", table: "WorkTasks");
        migrationBuilder.DropColumn(name: "BranchId", table: "WorkTasks");
        migrationBuilder.DropColumn(name: "DepartmentId", table: "WorkTasks");
        migrationBuilder.DropColumn(name: "TemplateId", table: "WorkTasks");
        migrationBuilder.DropColumn(name: "SlaReminderHours", table: "WorkTasks");
        migrationBuilder.DropColumn(name: "AcceptedAt", table: "WorkTasks");
        migrationBuilder.DropColumn(name: "RejectionReason", table: "WorkTasks");
        migrationBuilder.DropColumn(name: "AssignmentNote", table: "WorkTasks");
    }
}
