using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>
/// Payslip.TravelHours/TravelSalary được thêm vào entity nhưng chưa từng có migration —
/// mọi query chạm bảng Payslips (kể cả gián tiếp, ví dụ CashTransactionsController.DeleteTransaction)
/// đều lỗi 500 "column p.TravelHours does not exist". Dùng IF NOT EXISTS để an toàn khi
/// migration history không khớp chính xác với schema thực tế.
/// </summary>
public partial class AddPayslipTravelFields : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(
            @"ALTER TABLE ""Payslips"" ADD COLUMN IF NOT EXISTS ""TravelHours"" numeric(18,2) NULL;");
        migrationBuilder.Sql(
            @"ALTER TABLE ""Payslips"" ADD COLUMN IF NOT EXISTS ""TravelSalary"" numeric(18,2) NULL;");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(@"ALTER TABLE ""Payslips"" DROP COLUMN IF EXISTS ""TravelHours"";");
        migrationBuilder.Sql(@"ALTER TABLE ""Payslips"" DROP COLUMN IF EXISTS ""TravelSalary"";");
    }
}
