using Microsoft.AspNetCore.Mvc;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>PLU tem cân: không trùng giữa các hàng, không tái dùng PLU của hàng đã xóa.</summary>
[Collection("pos-pg")]
public class PosScalePluTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static PosProductsController.PosProductUpsertDto Dto(string name, string? plu) => new(
        null, null, name, null, null, null, null, PosProductType.Goods, null, null, null,
        0, 100000, 0, false, 0, 0, 0, 0, null, null, "kg", true, false, null, null, ScalePlu: plu);

    [Fact]
    public async Task Khong_cho_hai_hang_cung_PLU()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await Fx.AddProductAsync(store, "Thịt", PosProductType.Goods, 10, 0, 150000, p => p.ScalePlu = "7");

        await using var db = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosProductsController(db, null!, null!, null!), store);
        var res = await ctl.CreateProduct(Dto("Cá", "00007"));   // «00007» chuẩn hóa = «7»
        var bad = Assert.IsType<BadRequestObjectResult>(res.Result);
        Assert.Contains("PLU 7", ((AppResponse<PosProductsController.PosProductDto>)bad.Value!).Message);

    }

    [Fact]
    public async Task Gan_PLU_bo_qua_PLU_cua_hang_da_xoa()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await Fx.AddProductAsync(store, "Rau", PosProductType.Goods, 10, 0, 20000, p => p.ScalePlu = "1");
        // Hàng đã xóa từng giữ PLU 2 — tem cũ còn dán ngoài quầy.
        await Fx.AddProductAsync(store, "Cá cũ", PosProductType.Goods, 0, 0, 90000, p =>
        {
            p.ScalePlu = "2";
            p.Deleted = DateTime.UtcNow;
        });
        var moi = await Fx.AddProductAsync(store, "Cá mới", PosProductType.Goods, 10, 0, 90000);

        await using var db = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosProductsController(db, null!, null!, null!), store);
        var data = Data(await ctl.AssignScalePlu(moi.Id));
        Assert.Equal("3", (string)data.GetType().GetProperty("scalePlu")!.GetValue(data)!); // trước đây = «2»
    }
}
