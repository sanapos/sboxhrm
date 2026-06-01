using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddBranchIdToEmployee : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // DB may never have had Devices.BranchId — use IF EXISTS so migrate does not abort.
            migrationBuilder.Sql(@"ALTER TABLE ""Devices"" DROP CONSTRAINT IF EXISTS ""FK_Devices_Branches_BranchId"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_Devices_BranchId"";");
            migrationBuilder.Sql(@"ALTER TABLE ""Devices"" DROP COLUMN IF EXISTS ""BranchId"";");

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000001"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 231, DateTimeKind.Local).AddTicks(6629));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000002"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 231, DateTimeKind.Local).AddTicks(6650));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000003"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 231, DateTimeKind.Local).AddTicks(6654));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000004"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 231, DateTimeKind.Local).AddTicks(6655));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000005"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 231, DateTimeKind.Local).AddTicks(6658));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000006"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 231, DateTimeKind.Local).AddTicks(6660));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000007"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 231, DateTimeKind.Local).AddTicks(6662));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000008"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 231, DateTimeKind.Local).AddTicks(6663));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000009"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 231, DateTimeKind.Local).AddTicks(6665));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(542));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(557));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(560));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(562));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(563));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(565));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(566));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(569));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(570));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(572));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(573));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(575));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(576));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(578));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(579));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(581));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(582));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(584));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(585));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111020"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(587));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111021"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(596));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111022"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(617));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111023"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(619));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111024"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(620));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111025"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(622));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111026"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(623));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111027"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(625));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111028"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(626));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111029"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(628));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111030"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(657));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111031"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(658));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111032"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(660));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111033"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(661));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111034"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(663));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111035"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(664));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111036"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(666));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111037"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(668));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111038"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(669));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111039"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(671));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111040"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(672));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111041"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(673));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111042"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 22, 27, 40, 236, DateTimeKind.Local).AddTicks(677));
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "BranchId",
                table: "Devices",
                type: "uuid",
                nullable: true);

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000001"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 970, DateTimeKind.Local).AddTicks(3929));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000002"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 970, DateTimeKind.Local).AddTicks(4015));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000003"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 970, DateTimeKind.Local).AddTicks(4024));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000004"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 970, DateTimeKind.Local).AddTicks(4027));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000005"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 970, DateTimeKind.Local).AddTicks(4029));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000006"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 970, DateTimeKind.Local).AddTicks(4031));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000007"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 970, DateTimeKind.Local).AddTicks(4033));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000008"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 970, DateTimeKind.Local).AddTicks(4035));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000009"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 970, DateTimeKind.Local).AddTicks(4037));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6578));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6593));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6595));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6597));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6598));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6600));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6602));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6604));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6606));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6608));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6609));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6611));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6612));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6614));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6616));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6617));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6619));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6621));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6622));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111020"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6627));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111021"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6634));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111022"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6665));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111023"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6667));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111024"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6668));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111025"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6670));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111026"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6671));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111027"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6673));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111028"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6674));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111029"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6676));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111030"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6677));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111031"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6679));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111032"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6681));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111033"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6682));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111034"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6684));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111035"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6685));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111036"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6687));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111037"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6688));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111038"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6690));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111039"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6691));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111040"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6693));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111041"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6694));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111042"),
                column: "CreatedAt",
                value: new DateTime(2026, 5, 8, 18, 37, 7, 974, DateTimeKind.Local).AddTicks(6696));

            migrationBuilder.CreateIndex(
                name: "IX_Devices_BranchId",
                table: "Devices",
                column: "BranchId");

            migrationBuilder.AddForeignKey(
                name: "FK_Devices_Branches_BranchId",
                table: "Devices",
                column: "BranchId",
                principalTable: "Branches",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }
    }
}
