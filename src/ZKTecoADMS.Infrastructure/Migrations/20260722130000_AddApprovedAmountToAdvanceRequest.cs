using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ZKTecoADMS.Infrastructure.Migrations;

/// <summary>
/// Cho phép quản lý duyệt yêu cầu ứng lương với số tiền thấp hơn số tiền nhân
/// viên yêu cầu ban đầu (AdvanceRequest.Amount). ApprovedAmount = null nghĩa
/// là chưa duyệt hoặc duyệt đủ số tiền yêu cầu (fallback dùng Amount).
/// Dùng IF NOT EXISTS theo quy ước migration gần đây của repo (an toàn khi
/// migration history không khớp chính xác với schema thực tế).
/// </summary>
public partial class AddApprovedAmountToAdvanceRequest : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(
            @"ALTER TABLE ""AdvanceRequests"" ADD COLUMN IF NOT EXISTS ""ApprovedAmount"" numeric(18,2) NULL;");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(@"ALTER TABLE ""AdvanceRequests"" DROP COLUMN IF EXISTS ""ApprovedAmount"";");
    }
}
