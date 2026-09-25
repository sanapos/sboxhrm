using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests;

public class PosQuoteCareBoardTests
{
    static readonly DateTime Now = new(2026, 9, 25, 3, 0, 0, DateTimeKind.Utc); // 10:00 giờ VN

    static PosQuote Quote(string no, decimal total, DateTime created) => new()
    {
        Id = Guid.NewGuid(), QuoteNo = no, Total = total, Status = PosQuoteStatus.Sent,
        CustomerName = "Khách " + no, CreatedAt = created,
    };

    static PosQuoteActivity Act(PosQuote q, DateTime at, string kind = "Call", int? score = null,
        DateTime? next = null, string content = "Gọi khách") => new()
    {
        Id = Guid.NewGuid(), QuoteId = q.Id, CreatedAt = at, Kind = kind,
        PotentialScore = score, NextFollowUpAt = next, Content = content,
    };

    [Fact]
    public void Scores_bands_trend_follow_ups_and_stale_customers()
    {
        var hot = Quote("BG1", 100_000_000, Now.AddDays(-20));
        var warm = Quote("BG2", 50_000_000, Now.AddDays(-20));
        var cold = Quote("BG3", 10_000_000, Now.AddDays(-30));
        var fresh = Quote("BG4", 5_000_000, Now.AddDays(-1));
        var acts = new List<PosQuoteActivity>
        {
            Act(hot, Now.AddDays(-5), score: 6),
            Act(hot, Now.AddDays(-2), score: 9, next: Now.AddHours(2)),           // hẹn hôm nay
            Act(warm, Now.AddDays(-6), score: 7),
            Act(warm, Now.AddDays(-4), score: 5, next: Now.AddDays(-1)),          // hẹn quá hạn
            Act(cold, Now.AddDays(-15), content: "[[TN:3]] Khách chê giá"),       // điểm cũ trong nội dung
            Act(cold, Now.AddDays(-14), kind: "Status", content: "Cập nhật trạng thái"),
        };

        var (sum, items) = PosQuoteCareBoard.Build([cold, fresh, warm, hot], acts, new Dictionary<Guid, string>(), Now);

        Assert.Equal(["BG2", "BG1", "BG3", "BG4"], items.Select(i => i.QuoteNo)); // quá hạn → hôm nay → điểm
        var h = items.Single(i => i.QuoteNo == "BG1");
        Assert.Equal((9, 6, 1, "hot", "today"), (h.Score!.Value, h.PreviousScore!.Value, h.Trend, h.Band, h.FollowUp));
        Assert.Equal([6, 9], h.ScoreHistory.Select(p => p.Score));
        var w = items.Single(i => i.QuoteNo == "BG2");
        Assert.Equal((5, -1, "warm", "overdue"), (w.Score!.Value, w.Trend, w.Band, w.FollowUp));
        var c = items.Single(i => i.QuoteNo == "BG3");
        Assert.Equal((3, "cold", true, "Khách chê giá", 1), (c.Score!.Value, c.Band, c.Stale, c.LastContent, c.ContactCount));
        var f = items.Single(i => i.QuoteNo == "BG4");
        Assert.Equal(("none", false, (int?)null), (f.Band, f.Stale, f.DaysSinceContact));

        Assert.Equal((4, 1, 1, 1, 1, 1, 1, 1), (sum.Total, sum.Hot, sum.Warm, sum.Cold, sum.Unscored, sum.Overdue, sum.DueToday, sum.Stale));
        Assert.Equal(5.7, sum.AverageScore);
        Assert.Equal(90_000_000 + 25_000_000 + 3_000_000m, sum.WeightedValue);
    }

    [Fact]
    public void Contact_after_a_follow_up_without_a_new_date_clears_it()
    {
        var q = Quote("BG9", 1, Now.AddDays(-10));
        var (_, items) = PosQuoteCareBoard.Build([q],
        [
            Act(q, Now.AddDays(-3), score: 4, next: Now.AddDays(-1)),
            Act(q, Now.AddHours(-1), kind: "Meeting", score: 8),
        ], new Dictionary<Guid, string>(), Now);
        var i = Assert.Single(items);
        Assert.Equal(("none", "hot", 1, "Meeting"), (i.FollowUp, i.Band, i.Trend, i.LastContactKind));
    }

    [Fact]
    public void Sanitizer_strips_file_and_network_access_but_keeps_layout_and_embedded_images()
    {
        const string html = """
            <html><head><meta http-equiv="refresh" content="0;url=file:///etc/passwd"><base href="file:///app/">
            <link rel="stylesheet" href="http://10.0.0.1/x.css"><style>@import url(file:///etc/x.css);
            td{background:url('file:///app/appsettings.json')} .ok{color:red}</style></head>
            <body onload="fetch('/x')"><h2 class="ok" ONCLICK='x()'>BÁO GIÁ</h2>
            <iframe src="file:///app/appsettings.json">x</iframe><object data="file:///etc/passwd"></object>
            <script>fetch('http://169.254.169.254/')</script><embed src="file:///etc/shadow">
            <img src="file:///etc/passwd"><img src=" data:image/png;base64,AAAA" width="10">
            <a href="http://evil/">link</a><a href="#top">top</a><img srcset="http://x/a.png 2x">
            <table><tr><td style="text-align:right">1.000.000</td></tr></table></body></html>
            """;
        var s = OfficePdfConverter.SanitizeHtml(html);
        foreach (var bad in new[] { "file:", "http:", "<iframe", "<object", "<script", "<embed", "<base", "<link", "<meta", "@import", "onload", "onclick" })
            Assert.DoesNotContain(bad, s, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("src=\" data:image/png;base64,AAAA\"", s);
        Assert.Contains("href=\"#top\"", s);
        Assert.Contains("<td style=\"text-align:right\">1.000.000</td>", s);
        Assert.Contains(".ok{color:red}", s);
        Assert.Contains("BÁO GIÁ", s);
    }

    [Fact]
    public async Task Html_template_renders_to_a4_pdf_with_chromium()
    {
        if (!File.Exists(@"C:\Program Files\Google\Chrome\Application\chrome.exe")
            && !File.Exists("/usr/bin/chromium")) return;
        var html = PosQuoteDocumentHtml.Build(
            new PosQuote { QuoteNo = "BG1", CustomerName = "Công ty Hòa Bình", Total = 1_000_000 },
            PosQuoteDocumentKind.Quote, "BG1", null);
        var pdf = await new OfficePdfConverter(NullLogger<OfficePdfConverter>.Instance).HtmlToPdfAsync(html, default);
        Assert.Equal("%PDF", System.Text.Encoding.ASCII.GetString(pdf, 0, 4));
        // Khổ A4 = 595 x 842 pt.
        Assert.Contains("/MediaBox [0 0 594.95996 841.91998]", System.Text.Encoding.Latin1.GetString(pdf));
    }
}
