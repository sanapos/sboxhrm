using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Báo cáo «Mạng cửa hàng»: kết luận, giờ đông, mất kết nối, gợi ý.</summary>
public class PosNetworkReportTests
{
    static readonly DateTime Day = new(2026, 10, 13, 0, 0, 0, DateTimeKind.Utc); // 07:00 giờ VN

    static PosNetworkSample S(string dev, DateTime at, int sent = 10, int failed = 0, int p95 = 120,
        int offline = 0, int rssi = -55, bool agent = false, int disc = 0, int pc = 0, int pf = 0) => new()
    {
        Id = Guid.NewGuid(), DeviceId = dev, DeviceName = dev, BucketStart = at, PingSent = sent,
        PingFailed = failed, PingP50Ms = p95 / 2, PingP95Ms = p95, PingMaxMs = p95, OfflineSec = offline,
        WifiRssi = rssi, IsAgent = agent, RealtimeDisconnects = disc, ConnType = "wifi",
        PrinterChecks = pc, PrinterFailed = pf,
    };

    static List<PosNetworkSample> Healthy(string dev, int hours, bool agent = false)
    {
        var list = new List<PosNetworkSample>();
        for (var i = 0; i < hours * 12; i++) list.Add(S(dev, Day.AddMinutes(5 * i), agent: agent));
        return list;
    }

    static PosNetworkReportBuilder.Report Build(List<PosNetworkSample> s, List<DateTime>? orders = null,
        List<PosNetworkReportBuilder.JobRow>? jobs = null) =>
        PosNetworkReportBuilder.Build(s, orders ?? [], jobs ?? [], Day, Day.AddDays(1));

    [Fact]
    public void Too_few_samples_is_insufficient()
    {
        var r = Build([S("a", Day)]);
        Assert.Equal("insufficient", r.Verdict);
    }

    [Fact]
    public void Healthy_network_is_green()
    {
        var r = Build(Healthy("t1", 4, agent: true).Concat(Healthy("phone", 4)).ToList(),
            Enumerable.Range(0, 40).Select(i => Day.AddMinutes(6 * i)).ToList());
        Assert.Equal("green", r.Verdict);
        Assert.True(r.Score >= 90);
        Assert.Equal(2, r.DeviceCount);
        Assert.Empty(r.Outages);
    }

    [Fact]
    public void Long_outage_in_business_hour_is_red_and_merged()
    {
        var s = Healthy("t1", 4, agent: true);
        // 3 khung liền nhau mất mạng 5 phút → 1 lần mất 15 phút.
        for (var i = 12; i < 15; i++) s[i] = S("t1", Day.AddMinutes(5 * i), failed: 10, offline: 300, agent: true);
        var r = Build(s, [Day.AddMinutes(65)]);
        Assert.Equal("red", r.Verdict);
        var o = Assert.Single(r.Outages, x => x.Kind.StartsWith("Mất kết nối máy"));
        Assert.Equal(900, o.Seconds);
        Assert.Contains(r.Recommendations, x => x.Code == "AGENT");
        Assert.Contains(r.Recommendations, x => x.Code == "OUTAGE");
    }

    [Fact]
    public void Peak_hour_degradation_is_detected()
    {
        var s = new List<PosNetworkSample>();
        var orders = new List<DateTime>();
        for (var h = 0; h < 8; h++)
        {
            var peak = h is 3;
            for (var k = 0; k < 12; k++)
                s.Add(S("t1", Day.AddHours(h).AddMinutes(5 * k), failed: peak ? 3 : 0, p95: peak ? 2500 : 150));
            for (var k = 0; k < (peak ? 40 : 5); k++) orders.Add(Day.AddHours(h).AddMinutes(k));
        }
        var r = Build(s, orders);
        Assert.True(r.DegradesAtPeak);
        Assert.Contains(r.Recommendations, x => x.Code == "PEAK");
        Assert.NotEqual("green", r.Verdict);
    }

    [Fact]
    public void Weak_wifi_and_flaky_lan_printer_get_recommendations()
    {
        var s = Healthy("bar", 2).Select(x => S("bar", x.BucketStart, rssi: -78, pc: 2, pf: 1)).ToList();
        var r = Build(s);
        Assert.Contains(r.Recommendations, x => x.Code == "WEAK_WIFI");
        Assert.Contains(r.Recommendations, x => x.Code == "PRINTER_LAN");
    }

    [Fact]
    public void Print_stats_count_stale_and_stuck()
    {
        var jobs = new List<PosNetworkReportBuilder.JobRow>
        {
            new(Day, Day.AddSeconds(2), PosPrintJobStatus.Completed, null),
            new(Day, Day.AddSeconds(4), PosPrintJobStatus.Completed, null),
            new(Day, null, PosPrintJobStatus.Cancelled, "STALE_QUEUED"),
            new(Day, null, PosPrintJobStatus.Cancelled, "STUCK_NO_REQUEUE"),
        };
        var r = Build(Healthy("t1", 2), jobs: jobs);
        Assert.Equal(4, r.Print.Total);
        Assert.Equal(1, r.Print.StaleQueued);
        Assert.Equal(1, r.Print.StuckNoRequeue);
        Assert.Contains(r.Recommendations, x => x.Code == "PRINT_JOBS");
    }

    [Fact]
    public void Score_matches_verdict_color()
    {
        // 6/10 lệnh in lỗi → đỏ dù ping tốt: điểm không được «xanh» (≥ 60).
        var jobs = Enumerable.Range(0, 10).Select(i => new PosNetworkReportBuilder.JobRow(
            Day, i < 4 ? Day.AddSeconds(2) : null,
            i < 4 ? PosPrintJobStatus.Completed : PosPrintJobStatus.Failed, null)).ToList();
        var red = Build(Healthy("t1", 4), jobs: jobs);
        Assert.Equal("red", red.Verdict);
        Assert.True(red.Score <= 59);

        var s = Healthy("t1", 4);
        // Rớt realtime ≥ 3 lần / giờ mới chập chờn (1 lần lẻ không đổi màu).
        s[20] = S("t1", s[20].BucketStart, disc: 3);
        var yellow = Build(s, [Day.AddMinutes(100)]);
        Assert.Equal("yellow", yellow.Verdict);
        Assert.InRange(yellow.Score, 0, 84);
    }

    [Fact]
    public void Many_realtime_drops_get_recommendation_and_plain_yellow_text()
    {
        var s = Healthy("t1", 4).Select((x, i) => i % 2 == 0 ? S("t1", x.BucketStart, disc: 1) : x).ToList();
        var r = Build(s, [Day.AddMinutes(100)]);
        Assert.Equal("yellow", r.Verdict);
        Assert.DoesNotContain("cao điểm", r.VerdictText);
        var rec = Assert.Single(r.Recommendations, x => x.Code == "REALTIME");
        Assert.Contains("t1", rec.Detail);
    }

    [Fact]
    public void Bucket_is_aligned_to_5_minutes_utc()
    {
        var b = PosNetworkController.AlignBucket(new DateTime(2026, 10, 13, 8, 7, 59, DateTimeKind.Utc));
        Assert.Equal(new DateTime(2026, 10, 13, 8, 5, 0, DateTimeKind.Utc), b);
    }
}
