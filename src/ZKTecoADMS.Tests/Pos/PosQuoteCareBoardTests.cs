using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Bảng theo dõi chăm sóc khách từ báo giá.</summary>
public class PosQuoteCareBoardTests
{
    static readonly DateTime Now = new(2026, 10, 10, 3, 0, 0, DateTimeKind.Utc); // 10:00 giờ VN

    static PosQuote Q(string no, string? phone, DateTime created) => new()
    {
        Id = Guid.NewGuid(), StoreId = Guid.Empty, QuoteNo = no, CustomerName = "Khách " + no,
        CustomerPhone = phone, Status = PosQuoteStatus.Sent, Total = 1_000_000, CreatedAt = created,
    };

    static PosQuoteActivity A(PosQuote q, string kind, DateTime at, DateTime? next = null, int? score = null) => new()
    {
        Id = Guid.NewGuid(), QuoteId = q.Id, Kind = kind, Content = kind, CreatedAt = at, NextFollowUpAt = next,
        PotentialScore = score,
    };

    [Fact]
    public void Thu_tien_va_cap_nhat_hop_dong_khong_tinh_la_lan_cham_soc()
    {
        var q = Q("BG1", "0905000111", Now.AddDays(-30));
        var acts = new[]
        {
            A(q, "Call", Now.AddDays(-20), score: 6),
            A(q, "Payment", Now.AddDays(-1)),
            A(q, "Contract", Now.AddHours(-2)),
        };
        var (_, items) = PosQuoteCareBoard.Build([q], acts, new Dictionary<Guid, string>(), Now);
        var i = Assert.Single(items);
        Assert.Equal(1, i.ContactCount);
        Assert.Equal("Call", i.LastContactKind);
        Assert.True(i.Stale);                    // 20 ngày chưa chăm sóc — thu tiền hôm qua không che mất
    }

    [Fact]
    public void Lien_he_o_bao_gia_khac_cung_khach_thi_khong_bi_coi_la_bo_quen()
    {
        var old = Q("BG-CU", "+84 905 000 111", Now.AddDays(-40));
        var cur = Q("BG-MOI", "0905000111", Now.AddDays(-15));
        var other = Q("BG-KHAC", "0911222333", Now.AddDays(-15));
        var acts = new[] { A(cur, "Call", Now.AddDays(-1), score: 8) };
        var (_, items) = PosQuoteCareBoard.Build([old, cur, other], acts, new Dictionary<Guid, string>(), Now);
        var byNo = items.ToDictionary(x => x.QuoteNo);
        Assert.False(byNo["BG-CU"].Stale);       // khách vừa được gọi hôm qua (qua báo giá mới)
        Assert.Equal(1, byNo["BG-CU"].OtherQuotes);
        Assert.NotNull(byNo["BG-CU"].CustomerLastContactAt);
        Assert.True(byNo["BG-KHAC"].Stale);      // khách khác vẫn bỏ quên
        Assert.Equal(0, byNo["BG-KHAC"].OtherQuotes);
    }

    [Fact]
    public void Hen_gan_nhat_qua_han_xep_dau_bang()
    {
        var a = Q("BG-A", null, Now.AddDays(-3));
        var b = Q("BG-B", null, Now.AddDays(-3));
        var acts = new[]
        {
            A(a, "Call", Now.AddDays(-2), next: Now.AddDays(-1), score: 5),
            A(b, "Call", Now.AddDays(-2), next: Now.AddDays(2), score: 9),
        };
        var (summary, items) = PosQuoteCareBoard.Build([a, b], acts, new Dictionary<Guid, string>(), Now);
        Assert.Equal("BG-A", items[0].QuoteNo);
        Assert.Equal("overdue", items[0].FollowUp);
        Assert.Equal(1, summary.Overdue);
    }
}
