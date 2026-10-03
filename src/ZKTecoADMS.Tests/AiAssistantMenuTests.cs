using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Tests;

public class AiAssistantMenuTests
{
    [Fact]
    public void Ban_do_menu_dung_ten_hien_tai()
    {
        Assert.Equal("Tài chính › Thưởng phạt", AiAssistantMenuMap.Paths["BonusPenalty"]);
        Assert.Contains("Báo cáo phân tích", AiAssistantMenuMap.Paths["HrAnalyticsReport"]);
        Assert.Contains("Duyệt chấm công", AiAssistantMenuMap.Paths["AttendanceApproval"]);
    }

    [Fact]
    public void The_open_chi_mo_muc_co_quyen_xem()
    {
        var perms = new Dictionary<string, ModulePermissionDto>
        {
            ["KPI"] = new() { Module = "KPI", CanView = true },
            ["Payroll"] = new() { Module = "Payroll", CanView = false },
        };
        var r = AiAssistantReplyParser.Parse(
            "Mở KPI cho bạn. [[OPEN:KPI]] [[OPEN:Payroll]] [[OPEN:KhongCo]]", perms, isSuperUser: false, [], "mở kpi");
        Assert.Equal(["open:KPI"], r.Actions);
        Assert.DoesNotContain("[[", r.Text);
    }
}
