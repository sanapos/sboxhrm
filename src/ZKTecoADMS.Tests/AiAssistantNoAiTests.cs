using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Cửa hàng CHƯA có khóa AI: bot nội bộ vẫn hiểu câu hỏi hỗ trợ và trả đúng hướng dẫn — không từ chối «cần AI» với câu hỏi
/// cách dùng, không trả menu chung khi hướng dẫn có câu trả lời, câu báo sự cố có dòng xử lý nhanh đúng nguyên nhân.
/// Bộ câu lấy từ lần rà 10/11/2026 (trước khi sửa: 20/42 câu đúng bài).
/// </summary>
public class AiAssistantNoAiTests
{
    static readonly IReadOnlyList<string> Acts =
        AiAssistantPermissionRules.AllowedActionTags(new Dictionary<string, ModulePermissionDto>(), isSuperUser: true);
    static readonly IReadOnlyList<string> Creates =
        AiAssistantPermissionRules.AllowedCreateExamples(new Dictionary<string, ModulePermissionDto>(), isSuperUser: true);

    static string Ask(string q) =>
        AiAssistantRuleBot.AnswerWithoutAi(q, "", AiAssistantHelpCorpus.Search(q, topK: 4), Acts, Creates, vietnamese: true).Reply;

    [Theory]
    // Hỏi cách dùng — kể cả câu có «tạo / xin nghỉ / đổi ca / mở ca» (trước đây bị từ chối «cần trợ lý AI»).
    [InlineData("Cách tạo phiếu phạt?", "Phiếu phạt")]
    [InlineData("cach tao phieu phat", "Phiếu phạt")]
    [InlineData("Làm sao để nhân viên chấm công bằng điện thoại?", "Chấm công Mobile")]
    [InlineData("Xin nghỉ phép thế nào", "GUIDE:advanced/leave")]
    [InlineData("Đổi ca với đồng nghiệp", "GUIDE:advanced/shift_swap")]
    [InlineData("Mở ca thu ngân", "GUIDE:pos/pos_eod")]
    [InlineData("Tạo combo như thế nào", "GUIDE:pos/pos_combo")]
    [InlineData("Thêm món mới vào menu", "GUIDE:pos/pos_products")]
    [InlineData("Hủy hóa đơn đã thanh toán thế nào", "GUIDE:pos/pos_after_sale")]
    [InlineData("Cách nhập hàng từ nhà cung cấp", "phiếu nhập")]
    [InlineData("Hướng dẫn kiểm kho", "GUIDE:pos/pos_stock_count")]
    [InlineData("Cách kết nối hóa đơn điện tử Viettel", "GUIDE:pos/pos_einvoice")]
    [InlineData("Cách đặt bàn trước cho khách", "GUIDE:pos/pos_booking")]
    [InlineData("Kết nối GHN để giao hàng", "GUIDE:pos/pos_shipping")]
    [InlineData("Gửi thông báo cho nhân viên qua Zalo", "GUIDE:advanced/zalo_bot")]
    [InlineData("Phân quyền cho thu ngân", "Phân quyền")]
    [InlineData("Quên mật khẩu đăng nhập", "quên mật khẩu")]
    [InlineData("Phần mềm có những chức năng gì", "GUIDE:basic/getting_started")]
    [InlineData("Trợ lý AI dùng thế nào", "GUIDE:advanced/ai_assistant")]
    public void Cau_hoi_cach_dung_ra_dung_bai(string q, string expected) =>
        Assert.Contains(expected, Ask(q), StringComparison.OrdinalIgnoreCase);

    [Theory]
    // Báo sự cố: dòng xử lý nhanh đúng nguyên nhân, kể cả viết tắt / từ thường ngày (HĐĐT, két, bị âm, không hiện).
    [InlineData("Sao không thanh toán được?", "Không thanh toán được: thiếu quyền")]
    [InlineData("máy in không in được", "Không in hóa đơn: máy in Online")]
    [InlineData("máy in bếp không ra phiếu", "Không gửi bếp được")]
    [InlineData("Báo không đủ tồn kho khi bán", "«Không đủ tồn kho»")]
    [InlineData("Tồn kho bị âm là sao", "Tồn âm: bán trước khi nhập")]
    [InlineData("Máy chấm công bị offline phải làm gì", "Máy ZK Offline")]
    [InlineData("Nhân viên không thấy menu bán hàng", "Không thấy menu: tài khoản thiếu quyền")]
    [InlineData("Màn hình phụ không hiện", "Màn hình phụ A6 trắng")]
    [InlineData("Két tiền lệch thì xử lý sao", "Lệch tiền:")]
    [InlineData("HĐĐT báo chờ ký", "chờ ký")]
    public void Bao_su_co_co_dong_xu_ly_nhanh(string q, string expected)
    {
        var reply = Ask(q);
        Assert.StartsWith("Cách xử lý nhanh:", reply);
        Assert.Contains(expected, reply);
    }

    [Theory]
    // Câu HỎI có từ thao tác không bị gắn lời nhắc «chưa lập phiếu»; câu RA LỆNH thì có.
    [InlineData("Xin nghỉ phép thế nào", false)]
    [InlineData("Bán hàng offline khi mất mạng được không", false)]
    [InlineData("Gửi thông báo cho nhân viên qua Zalo", true)]
    public void Loi_nhac_chi_cho_cau_ra_lenh(string q, bool note) =>
        Assert.Equal(note, Ask(q).StartsWith(AiAssistantRuleBot.NoAiActionNote));

    [Fact]
    public void Lenh_cu_the_khong_khop_bai_bao_can_AI() =>
        Assert.Equal(AiAssistantRuleBot.NoAiActionReply, Ask("Phạt An 50k đi trễ hôm nay"));

    [Fact]
    public void Hoi_so_lieu_bao_can_AI_va_chi_cho_xem()
    {
        Assert.StartsWith(AiAssistantRuleBot.NoAiDataNote, Ask("Doanh thu hôm nay bao nhiêu"));
        Assert.Equal(AiAssistantRuleBot.NoAiDataReply, Ask("Món nào bán chạy nhất"));
    }

    [Fact]
    public void Du_lieu_ca_nhan_van_tra_tu_ho_so()
    {
        Assert.StartsWith("Số dư phép", Ask("Tôi còn bao nhiêu ngày phép?"));
        Assert.StartsWith("Phiếu lương gần nhất", Ask("Phiếu lương tháng này"));
    }

    [Fact]
    public void Loi_chao_gioi_thieu_ca_ban_hang_lan_nhan_su()
    {
        var reply = Ask("xin chào");
        Assert.StartsWith("Xin chào!", reply);
        Assert.Contains("Bán hàng / POS", reply);
        Assert.DoesNotContain("dữ liệu HRM", reply);
    }

    [Fact]
    public void Khong_khop_ro_tra_bai_gan_nhat()
    {
        var reply = Ask("Cài đặt giá giờ vàng karaoke");
        Assert.StartsWith("Chưa có hướng dẫn đúng câu này — bài gần nhất:", reply);
        Assert.Contains("giờ vàng", reply);
    }

    [Theory]
    [InlineData("HĐĐT báo chờ ký", "HĐĐT")]
    [InlineData("két tiền lệch", "tiền mặt")]
    [InlineData("kết nối máy in", "kết nối máy in")]
    [InlineData("in bill", "hóa đơn")]
    public void Mo_rong_tu_viet_tat_nguyen_tu(string q, string contains) =>
        Assert.Contains(contains, AiAssistantHelpCorpus.Expand(q));
}
