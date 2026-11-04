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
    // Câu nói giao việc thường gặp — phải đi qua agent có công cụ lập thẻ, không rơi vào bot rule chỉ trả số liệu.
    [InlineData("Chi năm trăm nghìn tiền điện")]
    [InlineData("chi 500k tiền điện")]
    [InlineData("Thu 200 nghìn tiền khách trả")]
    [InlineData("Xin nghỉ ngày mai")]
    [InlineData("Mai cho An nghỉ")]
    [InlineData("Ứng cho tôi 2 triệu")]
    [InlineData("Nhập 10 thùng coca")]
    [InlineData("Bán 2 coca cho chị Lan")]
    [InlineData("Thêm khách hàng chị Lan số 0905123456")]
    [InlineData("Thêm nhà cung cấp Hòa Phát")]
    [InlineData("Cho Bình tăng ca tối nay")]
    [InlineData("Giao cho An dọn kho chiều nay")]
    [InlineData("Nhắc cả nhà họp lúc 3 giờ")]
    [InlineData("Xóa phiếu chi hôm qua")]
    [InlineData("Duyệt hết đơn nghỉ")]
    [InlineData("Hủy đơn vừa rồi")]
    [InlineData("Mở bàn 5")]
    [InlineData("Đặt bàn 7 giờ tối cho anh Nam")]
    [InlineData("Kiểm kho cà phê còn 10 gói")]
    [InlineData("Trả nhà cung cấp 5 triệu")]
    [InlineData("Chuyển 10 thùng coca sang chi nhánh 2")]
    [InlineData("Đổi giá trà sữa thành 30 nghìn")]
    [InlineData("Gửi thông báo nghỉ lễ cho cả công ty")]
    public void Cau_noi_giao_viec_la_lenh(string q) => Assert.True(AiAssistantIntent.LooksLikeAction(q), q);

    [Theory]
    [InlineData("Hôm nay có mấy đơn")]
    [InlineData("Chi nhánh 2 doanh thu bao nhiêu")]
    [InlineData("Chi phí tháng này bao nhiêu")]
    [InlineData("Ai đi trễ hôm nay")]
    public void Cau_hoi_so_lieu_khong_la_lenh(string q) => Assert.False(AiAssistantIntent.LooksLikeAction(q), q);

    [Theory]
    [InlineData("Mở phiếu lương", "Payslip")]
    [InlineData("mo phieu luong", "Payslip")]
    [InlineData("Mở giúp tôi màn hình bán hàng", "PosSell")]
    [InlineData("Vào báo cáo thu chi", "CashReport")]
    [InlineData("Mở bàn 5", null)]
    [InlineData("Mở ca", null)]
    [InlineData("Phiếu lương tháng này bao nhiêu", null)]
    [InlineData("Vào ngày nào lương về", null)]
    public void Lenh_mo_man(string q, string? expected) =>
        Assert.Equal(expected, AiAssistantIntent.OpenScreenTarget(q, _ => true));

    [Fact]
    public void Lenh_mo_man_khong_mo_man_khong_co_quyen() =>
        Assert.Null(AiAssistantIntent.OpenScreenTarget("Mở phiếu lương", _ => false));

    [Theory]
    [InlineData("Mở ca với 500k tiền đầu ca", "cash")]
    [InlineData("Thêm phòng ban Kinh doanh", "hr")]
    public void Viec_moi_vao_dung_nhom_cong_cu(string q, string group)
    {
        Assert.True(AiAssistantIntent.LooksLikeAction(q), q);
        Assert.Contains(group, AiAssistantIntent.Groups([q])!);
    }

    [Theory]
    [InlineData("Kinh doanh", "KD")]
    [InlineData("Kế toán", "KT2")]
    [InlineData("Phòng Kỹ thuật", "PKT")]
    public void Ma_phong_ban_tu_sinh_khong_trung(string name, string code) =>
        Assert.Equal(code, AiAssistantActions.DepartmentCode(name, ["KT"]));

    [Fact]
    public void Cach_day_la_moc_thoi_gian_khong_phai_hoi_cach_lam() =>
        Assert.False(AiAssistantIntent.IsGuideQuestion("Doanh thu cách đây 3 ngày", 200));

    [Theory]
    [InlineData("Đã xong [[NAV:abc]] nhé", "Đã xong  nhé")]
    [InlineData("Đã xong [[ACTION:nav_ca", "Đã xong")]
    public void The_la_khong_hien_thanh_chu(string reply, string expected) =>
        Assert.Equal(expected, AiAssistantReplyParser.Parse(reply, new Dictionary<string, ZKTecoADMS.Application.DTOs.Permissions.ModulePermissionDto>(), true, [], "").Text);

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
