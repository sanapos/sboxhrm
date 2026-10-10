using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Interceptors;

namespace ZKTecoADMS.Tests;

/// <summary>Lịch sử hủy / trả + che dữ liệu nhạy cảm trong Lịch sử thao tác.</summary>
public class PosCancelAuditTests
{
    [Fact]
    public void Clip_cat_theo_do_dai_cot()
    {
        Assert.Null(PosCancelAuditHelper.Clip("   ", 80));
        Assert.Equal("abc", PosCancelAuditHelper.Clip(" abc ", 80));
        var reason = new string('x', 200);
        var clipped = PosCancelAuditHelper.Clip(reason, 80)!;
        Assert.Equal(80, clipped.Length);
        Assert.EndsWith("…", clipped);
    }

    [Fact]
    public void ClipSlip_khong_vuot_gioi_han_cot()
    {
        var slip = new PosKitchenVoidSlip
        {
            ProductName = new string('m', 400),
            Reason = new string('r', 300),
            DetailNote = new string('d', 900),
        };
        PosCancelAuditHelper.ClipSlip(slip);
        Assert.Equal(200, slip.ProductName.Length);
        Assert.Equal(80, slip.Reason!.Length);
        Assert.Equal(500, slip.DetailNote!.Length);
    }

    [Fact]
    public void ProductSummary_gon_va_dem_mon_con_lai()
    {
        Assert.Null(PosCancelAuditHelper.ProductSummary(["", " "]));
        Assert.Equal("A, B", PosCancelAuditHelper.ProductSummary(["A", "B"]));
        Assert.Equal("A, B, C +2 món", PosCancelAuditHelper.ProductSummary(["A", "B", "C", "D", "E"]));
        var longNames = Enumerable.Range(0, 3).Select(_ => new string('n', 150)).ToList();
        Assert.True(PosCancelAuditHelper.ProductSummary(longNames)!.Length <= 200);
    }

    [Theory]
    [InlineData("ShippingFee", false)]
    [InlineData("ShippingAddress", false)]
    [InlineData("IsPinned", false)]
    [InlineData("PinnedAt", false)]
    [InlineData("PriceMapping", false)]
    [InlineData("Pin", true)]
    [InlineData("PinCode", true)]
    [InlineData("ManagerPin", true)]
    [InlineData("pos.manager_pin", true)]
    [InlineData("PasswordHash", true)]
    [InlineData("ApiKey", true)]
    public void IsSensitive_chi_che_dung_truong(string field, bool expected)
    {
        Assert.Equal(expected, ActivityAuditInterceptor.IsSensitive(field));
    }
}
