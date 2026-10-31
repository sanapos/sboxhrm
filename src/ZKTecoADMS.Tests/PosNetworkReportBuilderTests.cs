using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests;

/// <summary>Báo cáo «Mạng cửa hàng»: không kết luận sai vì 1 lần ping chậm, mẫu quá ít, rớt realtime lẻ, phiếu in lại sau.</summary>
public class PosNetworkReportBuilderTests
{
    static readonly DateTime T0 = new(2026, 10, 31, 3, 0, 0, DateTimeKind.Utc);

    static PosNetworkSample S(int minute, int sent = 10, int failed = 0, int p50 = 120, int p95 = 300, int max = 300,
        int disc = 0, string dev = "c20") => new()
    {
        Id = Guid.NewGuid(),
        DeviceId = dev,
        DeviceName = dev,
        BucketStart = T0.AddMinutes(minute),
        PingSent = sent,
        PingFailed = failed,
        PingP50Ms = p50,
        PingP95Ms = p95,
        PingMaxMs = max,
        RealtimeDisconnects = disc,
    };

    [Fact]
    public void Mot_lan_ping_cham_le_khong_thanh_p95_ca_gio()
    {
        // 12 khung × 10 ping nhanh; riêng 1 khung có 1 ping 3s (khung 10 ping thì p95 của khung = ping đó).
        // Trước: p95 của các p95 khung = 3000 → cả giờ «chậm». Thật: 1/120 ping chậm → p95 vẫn nhanh.
        var hour = Enumerable.Range(0, 11).Select(i => S(i * 5, p50: 100, p95: 150, max: 180)).ToList();
        hour.Add(S(55, p50: 100, p95: 3000, max: 3000));
        Assert.True(PosNetworkReportBuilder.LatencyP95(hour) < PosNetworkReportBuilder.GoodP95Ms);
    }

    [Fact]
    public void Mang_cham_that_van_bao_cham()
    {
        var hour = Enumerable.Range(0, 12).Select(i => S(i * 5, p50: 1500, p95: 2500, max: 3000)).ToList();
        Assert.True(PosNetworkReportBuilder.LatencyP95(hour) > PosNetworkReportBuilder.GoodP95Ms);
    }

    [Fact]
    public void It_ping_thi_khong_ket_luan_tre() =>
        Assert.Null(PosNetworkReportBuilder.LatencyP95([S(0, sent: 3, p95: 2900, max: 2900)]));

    [Fact]
    public void Mot_lan_loi_tren_vai_ping_khong_lam_do()
    {
        var samples = Enumerable.Range(0, 12).Select(i => S(i * 5)).ToList();
        samples[0] = S(0, sent: 2, failed: 1);
        var r = PosNetworkReportBuilder.Build(samples, [], [], T0, T0.AddHours(1));
        Assert.NotEqual("red", r.Verdict);
        Assert.NotEqual("red", r.Hours.Single().Health);
    }

    [Fact]
    public void Rot_realtime_le_khong_lam_vang_gio()
    {
        var samples = Enumerable.Range(0, 12).Select(i => S(i * 5)).ToList();
        samples[3] = S(15, disc: 1);
        var r = PosNetworkReportBuilder.Build(samples, [], [], T0, T0.AddHours(1));
        Assert.Equal("green", r.Hours.Single().Health);
        Assert.Equal("green", r.Verdict);
    }

    [Fact]
    public void Phieu_in_lai_sau_khong_tinh_thanh_thoi_gian_in()
    {
        // Tạo 10:00, bấm «In lại» 12:00 (hạn = 12:00 + 24h), xong 12:00:04 → 4 giây, không phải 2 giờ.
        var created = T0;
        var retried = T0.AddHours(2);
        var job = new PosNetworkReportBuilder.JobRow(created, retried.AddSeconds(4), PosPrintJobStatus.Completed, null,
            retried.AddHours(24));
        Assert.Equal(4, PosNetworkReportBuilder.PrintSec(job));
        // Báo xong muộn 2 giờ mà không «In lại» → bỏ khỏi thống kê.
        var late = new PosNetworkReportBuilder.JobRow(created, created.AddHours(2), PosPrintJobStatus.Completed, null,
            created.AddHours(24));
        Assert.Null(PosNetworkReportBuilder.PrintSec(late));
    }
}
