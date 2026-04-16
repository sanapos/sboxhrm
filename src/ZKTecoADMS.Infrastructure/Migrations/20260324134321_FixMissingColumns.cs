using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class FixMissingColumns : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"ALTER TABLE ""AppSettings"" DROP CONSTRAINT IF EXISTS ""FK_AppSettings_Stores_StoreId"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_AppSettings_Key"";");
            migrationBuilder.Sql(@"DROP INDEX IF EXISTS ""IX_AppSettings_StoreId"";");

            migrationBuilder.AddColumn<int>(
                name: "RenewalCount",
                table: "Stores",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<Guid>(
                name: "ServicePackageId",
                table: "Stores",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "TrialDays",
                table: "Stores",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTime>(
                name: "TrialStartDate",
                table: "Stores",
                type: "timestamp without time zone",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "ServicePackageId",
                table: "LicenseKeys",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "PlainTextPassword",
                table: "AspNetUsers",
                type: "text",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "ServicePackages",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Description = table.Column<string>(type: "text", nullable: true),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    DefaultDurationDays = table.Column<int>(type: "integer", nullable: false),
                    MaxUsers = table.Column<int>(type: "integer", nullable: false),
                    MaxDevices = table.Column<int>(type: "integer", nullable: false),
                    AllowedModules = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ServicePackages", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "KeyActivationPromotions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    ServicePackageId = table.Column<Guid>(type: "uuid", nullable: false),
                    StartDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    EndDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    Bonus1Key = table.Column<int>(type: "integer", nullable: false),
                    Bonus2Keys = table.Column<int>(type: "integer", nullable: false),
                    Bonus3Keys = table.Column<int>(type: "integer", nullable: false),
                    Bonus4Keys = table.Column<int>(type: "integer", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_KeyActivationPromotions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_KeyActivationPromotions_ServicePackages_ServicePackageId",
                        column: x => x.ServicePackageId,
                        principalTable: "ServicePackages",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(687));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(762));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(767));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(771));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(774));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(776));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(778));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(780));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 378, DateTimeKind.Local).AddTicks(782));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9584));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9611));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9614));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9615));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9617));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9619));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9621));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9623));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9625));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9627));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9629));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9630));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9632));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9633));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9635));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9636));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9638));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9639));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9641));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111020"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9643));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111021"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9661));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111022"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9686));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111023"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9688));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111024"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9690));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111025"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9692));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111026"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9767));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111027"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9769));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111028"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9771));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111029"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9773));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111030"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9777));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111031"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9779));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111032"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9781));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111033"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9782));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111034"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9784));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111035"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9786));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111036"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9787));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111037"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9789));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111038"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9790));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111039"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9792));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111040"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9793));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111041"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 24, 20, 43, 19, 381, DateTimeKind.Local).AddTicks(9794));

            migrationBuilder.CreateIndex(
                name: "IX_Stores_ServicePackageId",
                table: "Stores",
                column: "ServicePackageId");

            migrationBuilder.CreateIndex(
                name: "IX_LicenseKeys_ServicePackageId",
                table: "LicenseKeys",
                column: "ServicePackageId");

            migrationBuilder.CreateIndex(
                name: "IX_AppSettings_StoreId_Key",
                table: "AppSettings",
                columns: new[] { "StoreId", "Key" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_KeyActivationPromotions_ServicePackageId",
                table: "KeyActivationPromotions",
                column: "ServicePackageId");

            migrationBuilder.AddForeignKey(
                name: "FK_AppSettings_Stores_StoreId",
                table: "AppSettings",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_LicenseKeys_ServicePackages_ServicePackageId",
                table: "LicenseKeys",
                column: "ServicePackageId",
                principalTable: "ServicePackages",
                principalColumn: "Id");

            migrationBuilder.AddForeignKey(
                name: "FK_Stores_ServicePackages_ServicePackageId",
                table: "Stores",
                column: "ServicePackageId",
                principalTable: "ServicePackages",
                principalColumn: "Id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_AppSettings_Stores_StoreId",
                table: "AppSettings");

            migrationBuilder.DropForeignKey(
                name: "FK_LicenseKeys_ServicePackages_ServicePackageId",
                table: "LicenseKeys");

            migrationBuilder.DropForeignKey(
                name: "FK_Stores_ServicePackages_ServicePackageId",
                table: "Stores");

            migrationBuilder.DropTable(
                name: "KeyActivationPromotions");

            migrationBuilder.DropTable(
                name: "ServicePackages");

            migrationBuilder.DropIndex(
                name: "IX_Stores_ServicePackageId",
                table: "Stores");

            migrationBuilder.DropIndex(
                name: "IX_LicenseKeys_ServicePackageId",
                table: "LicenseKeys");

            migrationBuilder.DropIndex(
                name: "IX_AppSettings_StoreId_Key",
                table: "AppSettings");

            migrationBuilder.DropColumn(
                name: "RenewalCount",
                table: "Stores");

            migrationBuilder.DropColumn(
                name: "ServicePackageId",
                table: "Stores");

            migrationBuilder.DropColumn(
                name: "TrialDays",
                table: "Stores");

            migrationBuilder.DropColumn(
                name: "TrialStartDate",
                table: "Stores");

            migrationBuilder.DropColumn(
                name: "ServicePackageId",
                table: "LicenseKeys");

            migrationBuilder.DropColumn(
                name: "PlainTextPassword",
                table: "AspNetUsers");

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9554));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9580));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9583));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9585));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9587));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9589));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9591));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9592));

            migrationBuilder.UpdateData(
                table: "NotificationCategories",
                keyColumn: "Id",
                keyValue: new Guid("a0000001-0000-0000-0000-000000000009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 49, DateTimeKind.Local).AddTicks(9594));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3345));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3366));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3368));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3370));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3372));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3373));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3375));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3377));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3379));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3380));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3382));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3383));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3385));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3386));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3388));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3390));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3391));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3393));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3394));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111020"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3396));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111021"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3416));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111022"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3440));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111023"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3451));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111024"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3453));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111025"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3454));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111026"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3456));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111027"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3458));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111028"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3459));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111029"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3461));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111030"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3462));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111031"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3464));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111032"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3465));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111033"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3467));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111034"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3468));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111035"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3471));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111036"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3472));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111037"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3474));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111038"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3475));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111039"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3477));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111040"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3478));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111041"),
                column: "CreatedAt",
                value: new DateTime(2026, 3, 20, 11, 45, 4, 55, DateTimeKind.Local).AddTicks(3480));

            migrationBuilder.CreateIndex(
                name: "IX_AppSettings_Key",
                table: "AppSettings",
                column: "Key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_AppSettings_StoreId",
                table: "AppSettings",
                column: "StoreId");

            migrationBuilder.AddForeignKey(
                name: "FK_AppSettings_Stores_StoreId",
                table: "AppSettings",
                column: "StoreId",
                principalTable: "Stores",
                principalColumn: "Id");
        }
    }
}
