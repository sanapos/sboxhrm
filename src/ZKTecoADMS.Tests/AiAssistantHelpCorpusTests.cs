using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Trợ lý AI dùng đúng hướng dẫn sử dụng của app (HelpCorpus/landing-guide.json, xuất từ flutter_client):
/// đủ mọi bước, mở được mọi mục kể cả ngành hàng, nút điều hướng có thật.
/// </summary>
public class AiAssistantHelpCorpusTests
{
    [Fact]
    public void Doc_du_moi_buoc_huong_dan_cua_app()
    {
        var all = AiAssistantHelpCorpus.All;
        Assert.True(all.Count >= 60, $"chỉ có {all.Count} bước");
        foreach (var mode in AiAssistantHelpCorpus.Modes)
            Assert.Contains(all, c => c.Mode == mode);
        Assert.Equal(all.Count, all.Select(c => c.StepId).Distinct().Count());
        Assert.All(all, c =>
        {
            Assert.False(string.IsNullOrWhiteSpace(c.Title), c.StepId);
            Assert.NotEmpty(c.Bullets);
        });
    }

    [Fact]
    public void Moi_buoc_co_lop_tu_khoa_rieng_va_khong_thua()
    {
        var ids = AiAssistantHelpCorpus.All.Select(c => c.StepId).ToHashSet();
        Assert.Empty(ids.Except(AiAssistantHelpCorpus.Overlays.Keys));
        Assert.Empty(AiAssistantHelpCorpus.Overlays.Keys.Except(ids));
    }

    [Fact]
    public void Nut_dieu_huong_deu_co_that()
    {
        var known = AiAssistantPermissionRules.AllowedActionTags(new Dictionary<string, ModulePermissionDto>(), isSuperUser: true);
        foreach (var c in AiAssistantHelpCorpus.All)
            foreach (var tag in c.ActionTags)
                Assert.True(known.Contains(tag), $"{c.StepId}: {tag}");
    }

    [Theory]
    [InlineData("industry/ind_hotel", "industry", "ind_hotel")]
    [InlineData("pos/pos_einvoice", "pos", "pos_einvoice")]
    // AI ghi nhầm mục: vẫn mở đúng bước (tài khoản nằm ở mục Triển khai).
    [InlineData("advanced/employee_account", "basic", "employee_account")]
    public void The_GUIDE_mo_dung_buoc(string tag, string mode, string stepId)
    {
        Assert.True(AiAssistantHelpCorpus.TryParseGuideTag(tag, out var m, out var s));
        Assert.Equal(mode, m);
        Assert.Equal(stepId, s);
    }

    [Fact]
    public void The_GUIDE_buoc_khong_co_bi_bo()
    {
        Assert.False(AiAssistantHelpCorpus.TryParseGuideTag("basic/khong_co", out _, out _));
        Assert.False(AiAssistantHelpCorpus.TryParseGuideTag("ind_hotel", out _, out _));
    }

    [Theory]
    [InlineData("karaoke tính tiền giờ thế nào", "ind_room_hourly")]
    [InlineData("cách tạo phiếu ứng lương", "advance")]
    [InlineData("kết nối hóa đơn điện tử viettel", "pos_einvoice")]
    [InlineData("đổi ca với đồng nghiệp", "shift_swap")]
    public void Tim_dung_buoc_theo_cau_hoi(string query, string stepId)
    {
        var hits = AiAssistantHelpCorpus.Search(query, topK: 3);
        Assert.Contains(hits, h => h.StepId == stepId);
    }

    [Fact]
    public void Noi_dung_gui_AI_theo_menu_hien_tai_va_kem_chu_thich_anh()
    {
        var text = AiAssistantHelpCorpus.FormatForPrompt(AiAssistantHelpCorpus.Search("cách tạo phiếu ứng lương", topK: 1));
        Assert.Contains("[[GUIDE:basic/advance]]", text);
        Assert.Contains("Tài chính nhân sự", text);
        Assert.Contains("Trên màn hình:", text);
    }
}
