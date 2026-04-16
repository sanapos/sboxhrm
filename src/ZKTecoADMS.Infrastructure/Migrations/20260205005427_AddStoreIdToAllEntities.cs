using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddStoreIdToAllEntities : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "WorkSchedules",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "TaxSettings",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "ShiftTemplates",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "Shifts",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "SalaryProfiles",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "PenaltySettings",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "Payslips",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "Notifications",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "Leaves",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "InsuranceSettings",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "Holidays",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "Employees",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "AttendanceCorrectionRequests",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "Allowances",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "StoreId",
                table: "AdvanceRequests",
                type: "uuid",
                nullable: true);

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4580));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4598));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4599));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4601));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4603));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4604));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4606));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4607));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4609));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4610));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4612));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4613));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4615));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4617));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4618));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4619));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4621));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4622));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 7, 54, 26, 741, DateTimeKind.Local).AddTicks(4624));

            migrationBuilder.CreateIndex(
                name: "IX_WorkSchedules_StoreId",
                table: "WorkSchedules",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_TaxSettings_StoreId",
                table: "TaxSettings",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_ShiftTemplates_StoreId",
                table: "ShiftTemplates",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Shifts_StoreId",
                table: "Shifts",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_SalaryProfiles_StoreId",
                table: "SalaryProfiles",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_PenaltySettings_StoreId",
                table: "PenaltySettings",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Payslips_StoreId",
                table: "Payslips",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Notifications_StoreId",
                table: "Notifications",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Leaves_StoreId",
                table: "Leaves",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_InsuranceSettings_StoreId",
                table: "InsuranceSettings",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Holidays_StoreId",
                table: "Holidays",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Employees_StoreId",
                table: "Employees",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_AttendanceCorrectionRequests_StoreId",
                table: "AttendanceCorrectionRequests",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_Allowances_StoreId",
                table: "Allowances",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_AdvanceRequests_StoreId",
                table: "AdvanceRequests",
                column: "StoreId");

            migrationBuilder.AddForeignKey(
                name: "FK_AdvanceRequests_Stores_StoreId",
                table: "AdvanceRequests",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Allowances_Stores_StoreId",
                table: "Allowances",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_AttendanceCorrectionRequests_Stores_StoreId",
                table: "AttendanceCorrectionRequests",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Employees_Stores_StoreId",
                table: "Employees",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Holidays_Stores_StoreId",
                table: "Holidays",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_InsuranceSettings_Stores_StoreId",
                table: "InsuranceSettings",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Leaves_Stores_StoreId",
                table: "Leaves",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Notifications_Stores_StoreId",
                table: "Notifications",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Payslips_Stores_StoreId",
                table: "Payslips",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_PenaltySettings_Stores_StoreId",
                table: "PenaltySettings",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_SalaryProfiles_Stores_StoreId",
                table: "SalaryProfiles",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Shifts_Stores_StoreId",
                table: "Shifts",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_ShiftTemplates_Stores_StoreId",
                table: "ShiftTemplates",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_TaxSettings_Stores_StoreId",
                table: "TaxSettings",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_WorkSchedules_Stores_StoreId",
                table: "WorkSchedules",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AdvanceRequests_Stores_StoreId",
                table: "AdvanceRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_Allowances_Stores_StoreId",
                table: "Allowances");

            migrationBuilder.DropForeignKey(
                name: "FK_AttendanceCorrectionRequests_Stores_StoreId",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropForeignKey(
                name: "FK_Employees_Stores_StoreId",
                table: "Employees");

            migrationBuilder.DropForeignKey(
                name: "FK_Holidays_Stores_StoreId",
                table: "Holidays");

            migrationBuilder.DropForeignKey(
                name: "FK_InsuranceSettings_Stores_StoreId",
                table: "InsuranceSettings");

            migrationBuilder.DropForeignKey(
                name: "FK_Leaves_Stores_StoreId",
                table: "Leaves");

            migrationBuilder.DropForeignKey(
                name: "FK_Notifications_Stores_StoreId",
                table: "Notifications");

            migrationBuilder.DropForeignKey(
                name: "FK_Payslips_Stores_StoreId",
                table: "Payslips");

            migrationBuilder.DropForeignKey(
                name: "FK_PenaltySettings_Stores_StoreId",
                table: "PenaltySettings");

            migrationBuilder.DropForeignKey(
                name: "FK_SalaryProfiles_Stores_StoreId",
                table: "SalaryProfiles");

            migrationBuilder.DropForeignKey(
                name: "FK_Shifts_Stores_StoreId",
                table: "Shifts");

            migrationBuilder.DropForeignKey(
                name: "FK_ShiftTemplates_Stores_StoreId",
                table: "ShiftTemplates");

            migrationBuilder.DropForeignKey(
                name: "FK_TaxSettings_Stores_StoreId",
                table: "TaxSettings");

            migrationBuilder.DropForeignKey(
                name: "FK_WorkSchedules_Stores_StoreId",
                table: "WorkSchedules");

            migrationBuilder.DropIndex(
                name: "IX_WorkSchedules_StoreId",
                table: "WorkSchedules");

            migrationBuilder.DropIndex(
                name: "IX_TaxSettings_StoreId",
                table: "TaxSettings");

            migrationBuilder.DropIndex(
                name: "IX_ShiftTemplates_StoreId",
                table: "ShiftTemplates");

            migrationBuilder.DropIndex(
                name: "IX_Shifts_StoreId",
                table: "Shifts");

            migrationBuilder.DropIndex(
                name: "IX_SalaryProfiles_StoreId",
                table: "SalaryProfiles");

            migrationBuilder.DropIndex(
                name: "IX_PenaltySettings_StoreId",
                table: "PenaltySettings");

            migrationBuilder.DropIndex(
                name: "IX_Payslips_StoreId",
                table: "Payslips");

            migrationBuilder.DropIndex(
                name: "IX_Notifications_StoreId",
                table: "Notifications");

            migrationBuilder.DropIndex(
                name: "IX_Leaves_StoreId",
                table: "Leaves");

            migrationBuilder.DropIndex(
                name: "IX_InsuranceSettings_StoreId",
                table: "InsuranceSettings");

            migrationBuilder.DropIndex(
                name: "IX_Holidays_StoreId",
                table: "Holidays");

            migrationBuilder.DropIndex(
                name: "IX_Employees_StoreId",
                table: "Employees");

            migrationBuilder.DropIndex(
                name: "IX_AttendanceCorrectionRequests_StoreId",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropIndex(
                name: "IX_Allowances_StoreId",
                table: "Allowances");

            migrationBuilder.DropIndex(
                name: "IX_AdvanceRequests_StoreId",
                table: "AdvanceRequests");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "WorkSchedules");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "TaxSettings");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "ShiftTemplates");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "Shifts");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "SalaryProfiles");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "PenaltySettings");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "Payslips");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "Notifications");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "Leaves");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "InsuranceSettings");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "Holidays");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "AttendanceCorrectionRequests");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "Allowances");

            migrationBuilder.DropColumn(
                name: "StoreId",
                table: "AdvanceRequests");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9389));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9411));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9413));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9415));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9421));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9423));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9425));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9427));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9428));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9430));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9431));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9433));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9462));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9464));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9466));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9468));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9470));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9471));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 5, 6, 41, 22, 612, DateTimeKind.Local).AddTicks(9473));
        }
    }
}
