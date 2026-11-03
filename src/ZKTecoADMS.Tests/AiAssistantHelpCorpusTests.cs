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

    [Theory]
    // Gõ / nói không dấu vẫn trúng bước.
    [InlineData("karaoke tinh tien gio", "ind_room_hourly")]
    [InlineData("tao phieu ung luong", "advance")]
    public void Tim_khong_dau(string query, string stepId) =>
        Assert.Contains(AiAssistantHelpCorpus.Search(query, topK: 3), h => h.StepId == stepId);

    [Theory]
    [InlineData("máy in bếp không in được", true)]
    [InlineData("tại sao nhân viên không chấm công được", true)]
    [InlineData("cai dat hoa don dien tu o dau", true)]
    [InlineData("sao in bị lỗi", true)]
    [InlineData("lợi nhuận tháng này bao nhiêu", false)]
    [InlineData("trả lời giúp tôi doanh thu hôm nay", false)]
    public void Nhan_cau_hoi_cach_dung(string q, bool expected) =>
        Assert.Equal(expected, AiAssistantQueryTools.LooksLikeHowTo(q.ToLowerInvariant()));

    static bool Guide(string q)
    {
        var top = AiAssistantHelpCorpus.SearchScored(q, topK: 1);
        return AiAssistantIntent.IsGuideQuestion(q, top.Count > 0 ? top[0].Score : 0);
    }

    [Theory]
    // Hỏi cách dùng / sự cố → trả lời nội bộ từ hướng dẫn, không gọi Gemini (kể cả câu có «tạo», «báo cáo», «nhập hàng»).
    [InlineData("Cách kết nối hóa đơn điện tử?")]
    [InlineData("Sao máy in bếp không in?")]
    [InlineData("Hướng dẫn chấm công mobile")]
    [InlineData("Cách tạo phiếu phạt?")]
    [InlineData("Cách xem báo cáo doanh thu?")]
    [InlineData("Hướng dẫn nhập hàng")]
    [InlineData("cach tao phieu ung luong")]
    [InlineData("Đặt bàn trước cho khách ở đâu?")]
    public void Cau_hoi_cach_dung_tra_loi_noi_bo(string q) => Assert.True(Guide(q), q);

    [Theory]
    // Lệnh cụ thể / câu hỏi số liệu → vẫn để agent (đọc báo cáo thật, dựng thẻ).
    [InlineData("Tạo phiếu phạt An 50k đi trễ")]
    [InlineData("Hướng dẫn giúp tôi tạo phiếu phạt An 50k")]
    [InlineData("Doanh thu tháng này thế nào?")]
    [InlineData("Tại sao lợi nhuận tháng này giảm?")]
    [InlineData("Báo giá cho chị Lan 10 thùng Coca")]
    [InlineData("Hôm nay ai đi trễ?")]
    public void Lenh_va_cau_hoi_so_lieu_van_qua_agent(string q) => Assert.False(Guide(q), q);

    [Fact]
    public void Bot_noi_bo_tra_loi_bang_huong_dan()
    {
        const string q = "nhân viên không chấm công được trên điện thoại";
        Assert.True(Guide(q), q);
        var r = AiAssistantRuleBot.Build(q, "", AiAssistantHelpCorpus.Search(q, topK: 4), [], [], includeFallback: false,
            guideQuestion: true);
        Assert.True(r.Matched);
        Assert.Contains("mobile", r.Reply, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Tu_vo_nghia_khong_keo_diem()
    {
        // «tôi có thể … không» không được làm bước bất kỳ vượt ngưỡng nạp tự động.
        Assert.All(AiAssistantHelpCorpus.SearchScored("tôi có thể làm được không", topK: 3),
            h => Assert.True(h.Score < AiAssistantHelpCorpus.ConfidentScore, $"{h.Chunk.StepId}: {h.Score}"));
        Assert.True(AiAssistantHelpCorpus.SearchScored("kết nối hóa đơn điện tử viettel", topK: 1)[0].Score
                    >= AiAssistantHelpCorpus.ConfidentScore);
    }

    [Fact]
    public void Moi_buoc_biet_khu_va_nhom_de_chi_duong()
    {
        Assert.All(AiAssistantHelpCorpus.All, c =>
        {
            Assert.False(string.IsNullOrWhiteSpace(c.Area), c.StepId);
            Assert.StartsWith("Hướng dẫn ", c.Trail);
        });
        var stock = AiAssistantHelpCorpus.All.Single(c => c.StepId == "pos_inventory");
        Assert.Equal("Hướng dẫn POS › Kho hàng", stock.Trail);
        Assert.Contains("Mục hướng dẫn: Hướng dẫn POS › Kho hàng ›", AiAssistantHelpCorpus.FormatForPrompt([stock]));
    }

    [Fact]
    public void Noi_dung_gui_AI_theo_menu_hien_tai_va_kem_chu_thich_anh()
    {
        var text = AiAssistantHelpCorpus.FormatForPrompt(AiAssistantHelpCorpus.Search("cách tạo phiếu ứng lương", topK: 1));
        Assert.Contains("[[GUIDE:basic/advance]]", text);
        Assert.Contains("Tài chính nhân sự", text);
        Assert.Contains("Trên màn hình:", text);
    }

    [Theory]
    // Thử trên C20 03/11/2026: bài hóa đơn điện tử đứng đầu vì «in» khớp chuỗi con, «hóa đơn» trùng tiêu đề.
    [InlineData("Lam sao de ket noi may in hoa don qua LAN?")]
    [InlineData("Cách kết nối máy in hóa đơn qua LAN")]
    public void May_in_hoa_don_ra_bai_may_in_khong_ra_hddt(string query)
    {
        Assert.Equal("pos_printers", AiAssistantHelpCorpus.Search(query, topK: 4)[0].StepId);
        Assert.Equal(["pos_printers"], AiAssistantHelpCorpus.GuideAnswerHits(query).Select(h => h.StepId));
    }

    [Fact]
    public void Y_con_trong_huong_dan_thut_le_khong_lap_dau_cham()
    {
        var hit = AiAssistantHelpCorpus.All.Single(c => c.StepId == "pos_einvoice");
        var text = AiAssistantRuleBot.Build("cach xuat hoa don dien tu", "", [hit], [], [], includeFallback: false, guideQuestion: true).Reply;
        Assert.DoesNotContain("• •", text);
        Assert.Contains("   – Viettel", text);
    }
}
