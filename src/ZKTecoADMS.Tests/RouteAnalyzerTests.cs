using Xunit;
using ZKTecoADMS.Application.Services;
using P = ZKTecoADMS.Application.Services.RouteAnalyzer.GeoPoint;

namespace ZKTecoADMS.Tests;

/// <summary>Lộ trình trong ca: lọc nhiễu GPS, quãng đường, điểm dừng, mất tín hiệu.</summary>
public class RouteAnalyzerTests
{
    static readonly DateTime T0 = new(2026, 9, 28, 1, 0, 0, DateTimeKind.Utc);
    // ~0.009 độ vĩ ≈ 1 km
    const double Km = 0.009;

    [Fact]
    public void Khoang_cach_haversine_dung()
    {
        var d = RouteAnalyzer.DistanceMeters(10.0, 106.0, 10.0 + Km, 106.0);
        Assert.InRange(d, 990, 1010);
    }

    [Fact]
    public void Dung_yen_rung_GPS_khong_cong_quang_duong()
    {
        var pts = Enumerable.Range(0, 60)
            .Select(i => new P(10.0 + (i % 2 == 0 ? 0.00005 : -0.00005), 106.0, T0.AddMinutes(i), 10))
            .ToList();
        Assert.Equal(0, RouteAnalyzer.DistanceKm(RouteAnalyzer.Clean(pts)));
    }

    [Fact]
    public void Diem_nhay_va_sai_so_lon_bi_loai()
    {
        var pts = new List<P>
        {
            new(10.0, 106.0, T0, 10),
            new(10.0 + Km * 50, 106.0, T0.AddMinutes(1), 10), // nhảy 50 km trong 1 phút
            new(10.0 + Km, 106.0, T0.AddMinutes(3), 10),
            new(10.2, 106.2, T0.AddMinutes(4), 900),           // sai số 900 m
            new(0, 0, T0.AddMinutes(5)),
        };
        var clean = RouteAnalyzer.Clean(pts);
        Assert.Equal(2, clean.Count);
        Assert.InRange(RouteAnalyzer.DistanceKm(clean), 0.95, 1.05);
    }

    [Fact]
    public void Di_chuyen_dung_20_phut_roi_di_tiep()
    {
        var pts = new List<P>();
        // đi 2 km trong 10 phút
        for (var i = 0; i <= 10; i++) pts.Add(new P(10.0 + Km * 0.2 * i, 106.0, T0.AddMinutes(i), 10));
        // dừng 20 phút
        for (var i = 1; i <= 20; i++) pts.Add(new P(10.0 + Km * 2 + 0.00003 * (i % 3), 106.0, T0.AddMinutes(10 + i), 10));
        // đi tiếp 1 km
        for (var i = 1; i <= 5; i++) pts.Add(new P(10.0 + Km * 2 + Km * 0.2 * i, 106.0, T0.AddMinutes(30 + i), 10));

        var s = RouteAnalyzer.Analyze(pts);
        Assert.InRange(s.DistanceKm, 2.9, 3.1);
        var stop = Assert.Single(s.Stops);
        Assert.InRange(stop.Minutes, 19, 21);
        Assert.Empty(s.Gaps);
    }

    [Fact]
    public void Mat_tin_hieu_khi_dang_di_chuyen()
    {
        var pts = new List<P>
        {
            new(10.0, 106.0, T0),
            new(10.0 + Km * 0.1, 106.0, T0.AddMinutes(1)),
            new(10.0 + Km * 5, 106.0, T0.AddMinutes(40)), // 40 phút sau, cách 5 km
        };
        var gap = Assert.Single(RouteAnalyzer.Analyze(pts).Gaps);
        Assert.InRange(gap.Minutes, 38, 40);
    }

    [Fact]
    public void Giam_diem_giu_dau_cuoi()
    {
        var pts = Enumerable.Range(0, 5000).Select(i => new P(10.0 + i * 0.00001, 106.0, T0.AddSeconds(i * 5))).ToList();
        var d = RouteAnalyzer.Downsample(pts, 1000);
        Assert.True(d.Count <= 1000);
        Assert.Equal(pts[0], d[0]);
        Assert.Equal(pts[^1], d[^1]);
    }
}
