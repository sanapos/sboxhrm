using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Báo cáo chăm sóc khách theo khoảng ngày.</summary>
public class PosQuoteCareLogTests
{
    static readonly DateTime Now = new(2026, 10, 10, 3, 0, 0, DateTimeKind.Utc); // 10:00 ngày 10/10 giờ VN

    static PosQuote Q(string no, string? phone) => new()
    {
        Id = Guid.NewGuid(), StoreId = Guid.Empty, QuoteNo = no, CustomerName = "Khách " + no,
        CustomerPhone = phone, Status = PosQuoteStatus.Sent, Total = 1_000_000, CreatedAt = Now.AddDays(-30),
    };

    static PosQuoteActivity A(PosQuote q, string kind, DateTime at, DateTime? next = null, int? score = null) => new()
    {
        Id = Guid.NewGuid(), QuoteId = q.Id, Kind = kind, Content = kind, CreatedAt = at, NextFollowUpAt = next,
        PotentialScore = score,
    };

    [Fact]
    public void Dem_theo_loai_ngay_va_khach_bo_qua_thao_tac_he_thong()
    {
        var q1 = Q("BG1", "0905000111");
        var q2 = Q("BG2", "0905 000 111"); // cùng khách (SĐT viết khác)
        var q3 = Q("BG3", "0905000222");
        var acts = new List<PosQuoteActivity>
        {
            A(q1, "Call", Now.AddHours(-1), score: 7),
            A(q2, "Meeting", Now.AddDays(-1), score: 9),
            A(q3, "Note", Now.AddDays(-1)),
            A(q1, "Payment", Now.AddHours(-2)), // hệ thống — không tính
            A(q1, "Status", Now.AddHours(-3)),
        };
        var quotes = new[] { q1, q2, q3 }.ToDictionary(q => q.Id);
        var (s, days) = PosQuoteCareLog.Build(acts, acts, quotes, new DateOnly(2026, 10, 8), new DateOnly(2026, 10, 10), Now);

        Assert.Equal(3, s.Total);
        Assert.Equal(3, s.Quotes);
        Assert.Equal(2, s.Customers);
        Assert.Equal(1, s.ByKind["Call"]);
        Assert.Equal(1, s.ByKind["Meeting"]);
        Assert.Equal(1, s.ByKind["Note"]);
        Assert.Equal(8, s.AverageScore);
        Assert.Equal(["2026-10-08", "2026-10-09", "2026-10-10"], days.Select(d => d.Date));
        Assert.Equal([0, 2, 1], days.Select(d => d.Count));
    }

    [Fact]
    public void Ngay_theo_gio_viet_nam()
    {
        var q = Q("BG1", null);
        // 18:00 UTC ngày 9 = 01:00 ngày 10 giờ VN
        var acts = new List<PosQuoteActivity> { A(q, "Call", new DateTime(2026, 10, 9, 18, 0, 0, DateTimeKind.Utc)) };
        var (_, days) = PosQuoteCareLog.Build(acts, acts, new Dictionary<Guid, PosQuote> { [q.Id] = q },
            new DateOnly(2026, 10, 9), new DateOnly(2026, 10, 10), Now);
        Assert.Equal([0, 1], days.Select(d => d.Count));
    }

    [Fact]
    public void Hen_da_giu_qua_han_va_sap_toi()
    {
        var q1 = Q("BG1", "0905000111");
        var q2 = Q("BG2", "0905000222");
        var q3 = Q("BG3", "0905000333");
        var kept = A(q1, "Call", Now.AddDays(-5), next: Now.AddDays(-3));
        var keptFollow = A(q1, "Call", Now.AddDays(-3).AddHours(2));
        var missed = A(q2, "Call", Now.AddDays(-5), next: Now.AddDays(-2));
        var future = A(q3, "FollowUp", Now.AddDays(-1), next: Now.AddDays(2));
        var acts = new List<PosQuoteActivity> { kept, keptFollow, missed, future };
        var quotes = new[] { q1, q2, q3 }.ToDictionary(q => q.Id);
        var (s, _) = PosQuoteCareLog.Build(acts, acts, quotes, new DateOnly(2026, 10, 1), new DateOnly(2026, 10, 10), Now);

        Assert.Equal(3, s.FollowUps.Set);
        Assert.Equal(1, s.FollowUps.Done);
        Assert.Equal(1, s.FollowUps.Overdue);
        Assert.Equal(1, s.FollowUps.Upcoming);
    }
}
