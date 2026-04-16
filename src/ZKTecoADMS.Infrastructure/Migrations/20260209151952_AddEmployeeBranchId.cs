using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddEmployeeBranchId : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "BranchId",
                table: "Employees",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "Branches",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Description = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    Phone = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    Email = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    Address = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    City = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    District = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    Ward = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    Latitude = table.Column<double>(type: "double precision", nullable: true),
                    Longitude = table.Column<double>(type: "double precision", nullable: true),
                    ParentBranchId = table.Column<Guid>(type: "uuid", nullable: true),
                    ManagerId = table.Column<Guid>(type: "uuid", nullable: true),
                    IsHeadquarter = table.Column<bool>(type: "boolean", nullable: false),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
                    TaxCode = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    OpenTime = table.Column<TimeSpan>(type: "interval", nullable: true),
                    CloseTime = table.Column<TimeSpan>(type: "interval", nullable: true),
                    MaxEmployees = table.Column<int>(type: "integer", nullable: true),
                    StoreId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    UpdatedBy = table.Column<string>(type: "text", nullable: true),
                    CreatedBy = table.Column<string>(type: "text", nullable: true),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false),
                    LastModified = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    LastModifiedBy = table.Column<string>(type: "text", nullable: true),
                    Deleted = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    DeletedBy = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Branches", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Branches_Branches_ParentBranchId",
                        column: x => x.ParentBranchId,
                        principalTable: "Branches",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_Branches_Employees_ManagerId",
                        column: x => x.ManagerId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_Branches_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(350));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(379));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(381));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(383));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(385));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(386));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(388));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(398));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(399));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(401));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(403));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(410));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(412));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(413));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(415));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(416));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(419));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(420));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 22, 19, 50, 934, DateTimeKind.Local).AddTicks(422));

            migrationBuilder.CreateIndex(
                name: "IX_Employees_BranchId",
                table: "Employees",
                column: "BranchId");

            migrationBuilder.CreateIndex(
                name: "IX_Branches_ManagerId",
                table: "Branches",
                column: "ManagerId");

            migrationBuilder.CreateIndex(
                name: "IX_Branches_ParentBranchId",
                table: "Branches",
                column: "ParentBranchId");

            migrationBuilder.CreateIndex(
                name: "IX_Branches_StoreId_Code",
                table: "Branches",
                columns: new[] { "StoreId", "Code" },
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_Employees_Branches_BranchId",
                table: "Employees",
                column: "BranchId",
                principalTable: "Branches",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_Employees_Branches_BranchId",
                table: "Employees");

            migrationBuilder.DropTable(
                name: "Branches");

            migrationBuilder.DropIndex(
                name: "IX_Employees_BranchId",
                table: "Employees");

            migrationBuilder.DropColumn(
                name: "BranchId",
                table: "Employees");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8676));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8703));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8705));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8707));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8718));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8720));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8721));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8723));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8725));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8727));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8728));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8730));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8731));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8733));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8734));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8735));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8737));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8738));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 19, 22, 33, 202, DateTimeKind.Local).AddTicks(8740));
        }
    }
}
