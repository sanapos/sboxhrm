using Xunit;
using ZKTecoADMS.Api.Controllers;

namespace ZKTecoADMS.Tests;

/// <summary>Khoảng ngày báo cáo HĐĐT: giờ VN không kèm múi giờ phải đổi sang UTC (trừ 7h).</summary>
public class PosEInvoiceRangeTests
{
    [Fact]
    public void Gio_VN_khong_kem_mui_gio_doi_sang_utc()
    {
        var (f, t) = PosEInvoiceController.Range(new DateTime(2026, 10, 1, 0, 0, 0), new DateTime(2026, 10, 31, 23, 59, 59));
        Assert.Equal(new DateTime(2026, 9, 30, 17, 0, 0), f);
        Assert.Equal(new DateTime(2026, 10, 31, 16, 59, 59), t);
        Assert.Equal(DateTimeKind.Utc, f.Kind);
    }

    [Fact]
    public void Gia_tri_da_co_utc_thi_giu_nguyen()
    {
        var utc = new DateTime(2026, 10, 1, 5, 0, 0, DateTimeKind.Utc);
        var (f, _) = PosEInvoiceController.Range(utc, utc.AddDays(1));
        Assert.Equal(utc, f);
    }

    [Fact]
    public void Mac_dinh_30_ngay_gan_nhat_theo_gio_VN()
    {
        var (f, t) = PosEInvoiceController.Range(null, null);
        Assert.True((t - f).TotalDays is > 29.9 and < 30.1);
        Assert.Equal(17, f.Hour); // 00:00 VN = 17:00 UTC hôm trước
    }
}
