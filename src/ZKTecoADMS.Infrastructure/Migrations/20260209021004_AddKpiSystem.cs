using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddKpiSystem : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "KpiBonusRules",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    MinScore = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    MaxScore = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    BonusRate = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
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
                    table.PrimaryKey("PK_KpiBonusRules", x => x.Id);
                    table.ForeignKey(
                        name: "FK_KpiBonusRules_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "KpiConfigs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Code = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Description = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    Type = table.Column<int>(type: "integer", nullable: false),
                    Unit = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true),
                    Weight = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    TargetValue = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    MinValue = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: true),
                    MaxValue = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: true),
                    Frequency = table.Column<int>(type: "integer", nullable: false),
                    GoogleSheetColumnName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    SortOrder = table.Column<int>(type: "integer", nullable: false),
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
                    table.PrimaryKey("PK_KpiConfigs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_KpiConfigs_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "KpiPeriods",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Year = table.Column<int>(type: "integer", nullable: false),
                    Month = table.Column<int>(type: "integer", nullable: true),
                    Quarter = table.Column<int>(type: "integer", nullable: true),
                    PeriodStart = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    PeriodEnd = table.Column<DateTime>(type: "timestamp without time zone", nullable: false),
                    Frequency = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    GoogleSpreadsheetId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    GoogleSheetName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    LastSyncedAt = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
                    Notes = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
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
                    table.PrimaryKey("PK_KpiPeriods", x => x.Id);
                    table.ForeignKey(
                        name: "FK_KpiPeriods_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "KpiResults",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<Guid>(type: "uuid", nullable: false),
                    KpiConfigId = table.Column<Guid>(type: "uuid", nullable: false),
                    KpiPeriodId = table.Column<Guid>(type: "uuid", nullable: false),
                    ActualValue = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    TargetValue = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    CompletionRate = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    WeightedScore = table.Column<decimal>(type: "numeric(18,4)", precision: 18, scale: 4, nullable: false),
                    Notes = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    Source = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
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
                    table.PrimaryKey("PK_KpiResults", x => x.Id);
                    table.ForeignKey(
                        name: "FK_KpiResults_Employees_EmployeeId",
                        column: x => x.EmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_KpiResults_KpiConfigs_KpiConfigId",
                        column: x => x.KpiConfigId,
                        principalTable: "KpiConfigs",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_KpiResults_KpiPeriods_KpiPeriodId",
                        column: x => x.KpiPeriodId,
                        principalTable: "KpiPeriods",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_KpiResults_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "KpiSalaries",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    EmployeeId = table.Column<Guid>(type: "uuid", nullable: false),
                    KpiPeriodId = table.Column<Guid>(type: "uuid", nullable: false),
                    BaseSalary = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    TotalKpiScore = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    KpiBonusRate = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    KpiBonusAmount = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Allowances = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    OtherBonus = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Deductions = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    GrossIncome = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    NetIncome = table.Column<decimal>(type: "numeric(18,2)", precision: 18, scale: 2, nullable: false),
                    Currency = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    Notes = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    IsApproved = table.Column<bool>(type: "boolean", nullable: false),
                    ApprovedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    ApprovedDate = table.Column<DateTime>(type: "timestamp without time zone", nullable: true),
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
                    table.PrimaryKey("PK_KpiSalaries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_KpiSalaries_AspNetUsers_ApprovedByUserId",
                        column: x => x.ApprovedByUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_KpiSalaries_Employees_EmployeeId",
                        column: x => x.EmployeeId,
                        principalTable: "Employees",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_KpiSalaries_KpiPeriods_KpiPeriodId",
                        column: x => x.KpiPeriodId,
                        principalTable: "KpiPeriods",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_KpiSalaries_Stores_StoreId",
                        column: x => x.StoreId,
                        principalTable: "Stores",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(4973));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(4995));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(4998));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5001));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5008));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5009));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5011));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5012));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5014));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5016));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5020));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5021));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5024));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5026));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5028));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5031));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5032));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5035));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 9, 9, 10, 2, 411, DateTimeKind.Local).AddTicks(5036));

            migrationBuilder.CreateIndex(
                name: "IX_KpiBonusRule_Store_SortOrder",
                table: "KpiBonusRules",
                columns: new[] { "StoreId", "SortOrder" });

            migrationBuilder.CreateIndex(
                name: "IX_KpiConfig_Code_StoreId",
                table: "KpiConfigs",
                columns: new[] { "Code", "StoreId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_KpiConfigs_StoreId",
                table: "KpiConfigs",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_KpiPeriod_Year_Month_StoreId",
                table: "KpiPeriods",
                columns: new[] { "Year", "Month", "StoreId" });

            migrationBuilder.CreateIndex(
                name: "IX_KpiPeriods_StoreId",
                table: "KpiPeriods",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_KpiResult_Employee_Config_Period",
                table: "KpiResults",
                columns: new[] { "EmployeeId", "KpiConfigId", "KpiPeriodId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_KpiResults_KpiConfigId",
                table: "KpiResults",
                column: "KpiConfigId");

            migrationBuilder.CreateIndex(
                name: "IX_KpiResults_KpiPeriodId",
                table: "KpiResults",
                column: "KpiPeriodId");

            migrationBuilder.CreateIndex(
                name: "IX_KpiResults_StoreId",
                table: "KpiResults",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_KpiSalaries_ApprovedByUserId",
                table: "KpiSalaries",
                column: "ApprovedByUserId");

            migrationBuilder.CreateIndex(
                name: "IX_KpiSalaries_KpiPeriodId",
                table: "KpiSalaries",
                column: "KpiPeriodId");

            migrationBuilder.CreateIndex(
                name: "IX_KpiSalaries_StoreId",
                table: "KpiSalaries",
                column: "StoreId");

            migrationBuilder.CreateIndex(
                name: "IX_KpiSalary_Employee_Period",
                table: "KpiSalaries",
                columns: new[] { "EmployeeId", "KpiPeriodId" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "KpiBonusRules");

            migrationBuilder.DropTable(
                name: "KpiResults");

            migrationBuilder.DropTable(
                name: "KpiSalaries");

            migrationBuilder.DropTable(
                name: "KpiConfigs");

            migrationBuilder.DropTable(
                name: "KpiPeriods");

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111001"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5424));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111002"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5449));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111003"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5451));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111004"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5453));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111005"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5454));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111006"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5456));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111007"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5458));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111008"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5471));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111009"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5473));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111010"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5477));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111011"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5479));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111012"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5488));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111013"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5490));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111014"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5493));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111015"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5495));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111016"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5497));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111017"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5498));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111018"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5500));

            migrationBuilder.UpdateData(
                table: "Permissions",
                keyColumn: "Id",
                keyValue: new Guid("11111111-1111-1111-1111-111111111019"),
                column: "CreatedAt",
                value: new DateTime(2026, 2, 7, 12, 44, 7, 766, DateTimeKind.Local).AddTicks(5501));
        }
    }
}
