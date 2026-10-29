using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Quyền «Hủy món đã gửi bếp» (PosSellVoidSent) và phép so giỏ với số đã báo bếp.</summary>
public class PosVoidKitchenSentTests
{
    static readonly Guid Tea = Guid.NewGuid();
    static readonly Guid Beer = Guid.NewGuid();

    static PosSaleOrderLine Sent(Guid product, decimal qty, decimal sent) =>
        new() { Id = Guid.NewGuid(), ProductId = product, Qty = qty, KitchenSentQty = sent };

    static PosSalesController.SaleLineDto Line(Guid product, decimal qty, string? note = null) =>
        new(product, qty, null, null, null, LineNote: note);

    [Fact]
    public void Bot_mon_da_bao_bep_la_huy_mon()
    {
        var prior = new[] { Sent(Tea, 3, 3) };
        Assert.True(PosSalesController.CutsKitchenSent(prior, [Line(Tea, 2)]));
        Assert.True(PosSalesController.CutsKitchenSent(prior, []));
    }

    [Fact]
    public void Bot_phan_chua_bao_bep_hoac_them_mon_khong_tinh()
    {
        var prior = new[] { Sent(Tea, 5, 3), Sent(Beer, 2, 0) };
        Assert.False(PosSalesController.CutsKitchenSent(prior, [Line(Tea, 3), Line(Beer, 0)]));
        Assert.False(PosSalesController.CutsKitchenSent(prior, [Line(Tea, 6), Line(Beer, 2)]));
    }

    [Fact]
    public void Doi_ghi_chu_hoac_tach_dong_cung_mon_khong_tinh_la_huy()
    {
        var prior = new[] { Sent(Tea, 2, 2) };
        Assert.False(PosSalesController.CutsKitchenSent(prior, [Line(Tea, 1, "ít đá"), Line(Tea, 1, "không đường")]));
    }

    [Fact]
    public void Mau_quyen_chi_chu_va_quan_ly_duoc_huy_mon_da_gui_bep()
    {
        Assert.True(PermissionPresetCatalog.Build("pos.director")["PosSellVoidSent"].A);
        Assert.True(PermissionPresetCatalog.Build("pos.manager")["PosSellVoidSent"].A);
        Assert.False(PermissionPresetCatalog.Build("pos.cashier").ContainsKey("PosSellVoidSent"));
        Assert.False(PermissionPresetCatalog.Build("pos.waiter").ContainsKey("PosSellVoidSent"));
        Assert.False(PermissionPresetCatalog.Build("pos.waiter")["PosSell"].A); // order không thanh toán
        var pos = new HashSet<string>(["PosSell"], StringComparer.OrdinalIgnoreCase);
        Assert.True(PermissionPresetCatalog.DefaultFlags("Manager", "PosSellVoidSent", pos).A); // quyền con theo Bán hàng
        Assert.False(PermissionPresetCatalog.DefaultFlags("Cashier", "PosSellVoidSent", pos).Any);
    }
}
