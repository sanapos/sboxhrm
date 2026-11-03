using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Định tuyến câu hỏi của Trợ lý ảo — các lỗi tìm thấy khi rà soát / thử trên C20 (03/11/2026): câu xin lời khuyên bị trả bài
/// hướng dẫn, chữ không dấu trùng nghĩa bị nhận là lệnh, bot rule trả dữ liệu của người hỏi khi hỏi về người khác.
/// </summary>
public class AiAssistantRoutingTests
{
    [Theory]
    [InlineData("Làm sao để tăng doanh thu tháng này?")]
    [InlineData("lam sao giam nhan vien di tre")]
    [InlineData("cách tăng lợi nhuận quán cafe")]
    public void Xin_loi_khuyen_khong_phai_hoi_cach_dung(string q) =>
        Assert.False(AiAssistantIntent.IsGuideQuestion(q, 200));

    [Theory]
    [InlineData("cách đăng ký tăng ca")]
    [InlineData("cach tao ma giam gia")]
    [InlineData("máy in bếp không in được")]
    public void Ten_chuc_nang_van_la_hoi_cach_dung(string q) =>
        Assert.True(AiAssistantIntent.IsGuideQuestion(q, 200));

    [Theory]
    [InlineData("ca phe sua da ban duoc bao nhieu", false)]
    [InlineData("so sanh doanh thu doi voi thang truoc", false)]
    [InlineData("khach hang thuong xuyen la ai", false)]
    [InlineData("Ứng dụng chạy chậm quá", false)]
    [InlineData("nuoc ep tao ban chay khong", false)]
    [InlineData("sua gia tra sua thanh 40k", true)]
    [InlineData("doi ca cho Lan sang chieu mai", true)]
    [InlineData("phat An 50k di tre", true)]
    [InlineData("tao phieu chi 50k tien dien", true)]
    [InlineData("them mon banh flan", true)]
    public void Lenh_khong_dau_khong_nhan_nham(string q, bool expected) =>
        Assert.Equal(expected, AiAssistantIntent.LooksLikeAction(q));

    [Theory]
    [InlineData("Lan còn bao nhiêu ngày phép?", true)]
    [InlineData("Lương tháng 10 của Hùng", true)]
    [InlineData("hôm nay bao nhiêu hội viên check-in", true)]
    [InlineData("Tôi còn bao nhiêu ngày phép?", false)]
    [InlineData("Lịch làm hôm nay", false)]
    [InlineData("con bao nhieu ngay phep", false)]
    public void Hoi_ve_nguoi_khac(string q, bool expected) =>
        Assert.Equal(expected, AiAssistantIntent.MentionsOthers(q));

    [Theory]
    [InlineData("Hôm nay bán được bao nhiêu?")]
    [InlineData("tai sao hom nay it khach")]
    public void Cau_so_lieu_di_agent(string q) => Assert.True(AiAssistantAgent.LooksAnalytical(q));

    [Fact]
    public void Tien_tra_khong_doc_duoc_thi_bao_loi_khong_mac_dinh_tra_du()
    {
        Assert.Equal(0m, AiAssistantActions.PaidAmount("ghi no", 100_000));
        Assert.Equal(0m, AiAssistantActions.PaidAmount("chưa trả", 100_000));
        Assert.Equal(100_000m, AiAssistantActions.PaidAmount(null, 100_000));
        Assert.Equal(50_000m, AiAssistantActions.PaidAmount("50 nghin", 100_000));
        Assert.ThrowsAny<Exception>(() => AiAssistantActions.PaidAmount("khach hen tuan sau", 100_000));
    }

    [Fact]
    public void Bot_rule_doc_cau_khong_dau_va_bang_cho_duyet_theo_pham_vi()
    {
        const string ctx = "=== PHIẾU PHẠT ===\n- PP001 | An | 50.000đ\n\n"
                           + "=== ĐƠN CHỜ DUYỆT (trong phạm vi bạn quản lý) ===\n- Nghỉ phép | Bình | 05/11\n";
        var penalty = AiAssistantRuleBot.Build("xem phieu phat", ctx, [], [], [], includeFallback: false).Reply;
        Assert.Contains("PP001", penalty);
        var pending = AiAssistantRuleBot.Build("đơn chờ duyệt", ctx, [], [], [], includeFallback: false).Reply;
        Assert.Contains("Bình", pending);
    }

    [Fact]
    public void Hoi_cach_khong_dau_gan_huong_dan() =>
        Assert.True(AiAssistantReplyParser.LooksLikeHowTo("cach tao combo"));

    [Fact]
    public void Prompt_co_mo_ta_SBOX_va_tra_loi_theo_ngon_ngu_cau_hoi()
    {
        var prompt = AiAssistantPromptBuilder.Build("", [], []);
        Assert.Contains("VỀ SBOX", prompt);
        Assert.Contains("KDS", prompt);
        Assert.Contains("ngôn ngữ khác", AiLanguage.AnswerRule("vi"));
    }
}
