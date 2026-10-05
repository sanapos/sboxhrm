using Microsoft.AspNetCore.Mvc;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>PLU tem cân (gán + quét), gợi ý nhập hàng.</summary>
[Collection("pos-pg")]
public class PosRetailScaleTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static object P(object o, string name) => o.GetType().GetProperty(name)!.GetValue(o)!;

    [Fact]
    public async Task Gan_PLU_so_nho_nhat_con_trong_va_quet_ma_PLU_ra_dung_hang()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var rau = await Fx.AddProductAsync(store, "Rau mồng tơi", PosProductType.Goods, 10, 0, 20000, p => p.ScalePlu = "1");
        var thit = await Fx.AddProductAsync(store, "Thịt ba chỉ", PosProductType.Goods, 10, 0, 150000);

        await using var db = Fx.NewDb();
        var products = PosPgFixture.As(new PosProductsController(db, null!, null!, null!), store);
        var plu = (string)P(Data(await products.AssignScalePlu(thit.Id)), "scalePlu");
        Assert.Equal("2", plu);
        // Gọi lại không đổi PLU.
        Assert.Equal("2", (string)P(Data(await products.AssignScalePlu(thit.Id)), "scalePlu"));

        // Tem cân mang PLU dạng 5 số ("00002") → tra ra đúng thịt.
        var res = await Sales(db, store).Lookup("00002");
        var data = Data(res);
        Assert.Equal("product", (string)P(data, "matchType"));
        Assert.Equal(thit.Id, (Guid)P(P(data, "product"), "Id"));
    }

    [Fact]
    public async Task Goi_y_nhap_hang_theo_ton_toi_da()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await Fx.AddProductAsync(store, "Sữa", PosProductType.Goods, 2, 8000, 10000, p => { p.MinStockQty = 5; p.MaxStockQty = 20; });
        await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 0, 5000, 7000, p => p.MinStockQty = 4);
        await Fx.AddProductAsync(store, "Kẹo", PosProductType.Goods, 50, 1000, 2000, p => p.MinStockQty = 10);

        await using var db = Fx.NewDb();
        var data = Data(await Reports(db, store).GetReorderSuggestions());
        Assert.Equal(2, (int)P(data, "count"));
        Assert.Equal(1, (int)P(data, "outOfStock"));
        var items = ((System.Collections.IEnumerable)P(data, "items")).Cast<object>().ToList();
        var sua = items.Single(i => (string)P(i, "name") == "Sữa");
        Assert.Equal(18m, (decimal)P(sua, "suggestQty"));   // 20 − 2
        var banh = items.Single(i => (string)P(i, "name") == "Bánh");
        Assert.Equal(8m, (decimal)P(banh, "suggestQty"));   // chưa đặt tối đa → 2 × 4 − 0
    }
}
