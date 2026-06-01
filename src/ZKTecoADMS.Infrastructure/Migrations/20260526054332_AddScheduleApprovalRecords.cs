using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <inheritdoc />
public partial class AddScheduleApprovalRecords : Migration
{
    /// <inheritdoc />
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<int>(
            name: "CurrentApprovalStep",
            table: "ScheduleRegistrations",
            type: "integer",
            nullable: false,
            defaultValue: 0);

        migrationBuilder.AddColumn<int>(
            name: "TotalApprovalLevels",
            table: "ScheduleRegistrations",
            type: "integer",
            nullable: false,
            defaultValue: 1);

        migrationBuilder.CreateTable(
            name: "ScheduleApprovalRecords",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                ScheduleRegistrationId = table.Column<Guid>(type: "uuid", nullable: false),
                StepOrder = table.Column<int>(type: "integer", nullable: false),
                StepName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                AssignedUserId = table.Column<Guid>(type: "uuid", nullable: true),
                AssignedUserName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                ActualUserId = table.Column<Guid>(type: "uuid", nullable: true),
                ActualUserName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                Status = table.Column<int>(type: "integer", nullable: false),
                Note = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                ActionDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                UpdatedBy = table.Column<string>(type: "text", nullable: true),
                CreatedBy = table.Column<string>(type: "text", nullable: true)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ScheduleApprovalRecords", x => x.Id);
                table.ForeignKey(
                    name: "FK_ScheduleApprovalRecords_AspNetUsers_ActualUserId",
                    column: x => x.ActualUserId,
                    principalTable: "AspNetUsers",
                    principalColumn: "Id");
                table.ForeignKey(
                    name: "FK_ScheduleApprovalRecords_AspNetUsers_AssignedUserId",
                    column: x => x.AssignedUserId,
                    principalTable: "AspNetUsers",
                    principalColumn: "Id");
                table.ForeignKey(
                    name: "FK_ScheduleApprovalRecords_ScheduleRegistrations_ScheduleRegis~",
                    column: x => x.ScheduleRegistrationId,
                    principalTable: "ScheduleRegistrations",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "IX_ScheduleApprovalRecords_ActualUserId",
            table: "ScheduleApprovalRecords",
            column: "ActualUserId");

        migrationBuilder.CreateIndex(
            name: "IX_ScheduleApprovalRecords_AssignedUserId",
            table: "ScheduleApprovalRecords",
            column: "AssignedUserId");

        migrationBuilder.CreateIndex(
            name: "IX_ScheduleApprovalRecords_ScheduleRegistrationId",
            table: "ScheduleApprovalRecords",
            column: "ScheduleRegistrationId");
    }

    /// <inheritdoc />
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "ScheduleApprovalRecords");

        migrationBuilder.DropColumn(
            name: "CurrentApprovalStep",
            table: "ScheduleRegistrations");

        migrationBuilder.DropColumn(
            name: "TotalApprovalLevels",
            table: "ScheduleRegistrations");
    }
}
