using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Bảng giá tự áp — dùng chung cho thu ngân và QR bàn / online (cùng một giá).</summary>
public class PosPriceListResolverTests
{
    static PosPriceList L(string name, bool isDefault = false, DateTime? from = null, DateTime? to = null) => new()
    {
        Id = Guid.NewGuid(), Name = name, IsDefault = isDefault, IsActive = true, ValidFrom = from, ValidTo = to,
    };

    [Fact]
    public void Uu_tien_bang_mac_dinh_con_hieu_luc()
    {
        var day = new DateTime(2026, 10, 4);
        var chung = L("Chung");
        var km = L("Khuyến mãi", isDefault: true, from: day.AddDays(-1), to: day.AddDays(1));
        Assert.Same(km, PosPriceListResolver.PickDefault([chung, km], day));
    }

    [Fact]
    public void Bang_mac_dinh_het_han_thi_ve_bang_khong_gioi_han_ngay()
    {
        var day = new DateTime(2026, 10, 4);
        var chung = L("Chung");
        var km = L("Khuyến mãi", isDefault: true, from: day.AddDays(-10), to: day.AddDays(-1));
        Assert.Same(chung, PosPriceListResolver.PickDefault([km, chung], day));
    }

    [Fact]
    public void Gia_theo_bien_the_don_vi_roi_ve_gia_hang()
    {
        var p = Guid.NewGuid();
        var u = Guid.NewGuid();
        var map = new Dictionary<string, decimal>
        {
            [PosPriceListResolver.ItemKey(p, null, null)] = 30000,
            [PosPriceListResolver.ItemKey(p, null, u)] = 45000,
        };
        Assert.Equal(45000, PosPriceListResolver.ResolvePrice(map, p, null, u));
        Assert.Equal(30000, PosPriceListResolver.ResolvePrice(map, p, null, Guid.NewGuid()));
        Assert.Null(PosPriceListResolver.ResolvePrice(map, Guid.NewGuid(), null, null));
    }
}
