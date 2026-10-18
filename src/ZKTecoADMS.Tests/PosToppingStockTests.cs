using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Topping khi bán / trả: định lượng NVL của topping, giá topping gửi lên, giá vốn theo topping.</summary>
public class PosToppingStockTests
{
    static readonly Guid StoreId = Guid.NewGuid();

    static ZKTecoDbContext NewDb() => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .Options);

    sealed record Shop(PosProduct Tea, PosProduct Pearl, PosProduct Starch, PosSaleOrder Order, PosSaleOrderLine Line);

    /// <summary>Trà sữa 2 ly, mỗi ly 1 phần trân châu; trân châu định lượng 30 g bột năng.</summary>
    static async Task<Shop> SeedAsync(ZKTecoDbContext db, bool pearlHasRecipe = true)
    {
        PosProduct P(string code, string name, PosProductType type, decimal onHand, decimal price, decimal cost = 0) => new()
        {
            Id = Guid.NewGuid(), StoreId = StoreId, ProductCode = code, Name = name, ProductType = type,
            OnHandQty = onHand, BasePrice = price, CostPrice = cost, IsActive = true,
            IsTopping = type == PosProductType.Topping,
        };
        var tea = P("HH00001", "Trà sữa", PosProductType.Goods, 10, 30000, 8000);
        var pearl = P("TP00001", "Trân châu", PosProductType.Topping, 0, 5000, 1000);
        var starch = P("NVL00001", "Bột năng", PosProductType.Material, 1000, 0, 20);
        db.PosProducts.AddRange(tea, pearl, starch);
        if (pearlHasRecipe)
        {
            db.PosProductRecipeLines.Add(new PosProductRecipeLine
            {
                Id = Guid.NewGuid(), StoreId = StoreId, ParentProductId = pearl.Id, ComponentProductId = starch.Id,
                Qty = 30, IsActive = true,
            });
        }
        var order = new PosSaleOrder { Id = Guid.NewGuid(), StoreId = StoreId, OrderNo = "HD0001", IsActive = true };
        var line = new PosSaleOrderLine
        {
            Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, ProductId = tea.Id, ProductName = tea.Name,
            Qty = 2, UnitPrice = 30000, LineTotal = 70000, IsActive = true,
            ToppingsJson = $$"""[{"id":"{{pearl.Id}}","name":"Trân châu","price":5000,"qty":1}]""",
        };
        db.PosSaleOrders.Add(order);
        db.PosSaleOrderLines.Add(line);
        await db.SaveChangesAsync();
        return new Shop(tea, pearl, starch, order, line);
    }

    static async Task SellAsync(ZKTecoDbContext db, Shop s)
    {
        // Như PrepareSaleStockAsync với dòng đã bung topping (InMemory không dịch được truy vấn biến thể của Prepare).
        var plan = new SaleStockPlan
        {
            Products = await db.PosProducts.AsTracking().ToDictionaryAsync(p => p.Id),
            RecipeLinesMap = (await db.PosProductRecipeLines.AsNoTracking().ToListAsync())
                .GroupBy(r => r.ParentProductId).ToDictionary(g => g.Key, g => g.ToList()),
            AllowNegativeStock = true,
        };
        await PosSaleStockHelper.ApplySaleStockAsync(db, StoreId, s.Order, [s.Line], plan, "tester");
        await db.SaveChangesAsync();
    }

    static async Task<decimal> OnHandAsync(ZKTecoDbContext db, Guid id) =>
        (await db.PosProducts.AsNoTracking().SingleAsync(p => p.Id == id)).OnHandQty;

    [Fact]
    public async Task Sale_topping_with_recipe_deducts_materials_not_the_topping()
    {
        using var db = NewDb();
        var s = await SeedAsync(db);
        await SellAsync(db, s);

        Assert.Equal(8, await OnHandAsync(db, s.Tea.Id));
        Assert.Equal(1000 - 2 * 30, await OnHandAsync(db, s.Starch.Id)); // 2 ly × 1 phần × 30 g
        Assert.Equal(0, await OnHandAsync(db, s.Pearl.Id)); // trước đây: −2
        Assert.Contains(await db.PosStockTransactions.ToListAsync(),
            t => t.ProductId == s.Starch.Id && t.Note == "Định lượng: Trân châu" && t.QtyChange == -60);
    }

    [Fact]
    public async Task Sale_topping_without_recipe_still_deducts_the_topping()
    {
        using var db = NewDb();
        var s = await SeedAsync(db, pearlHasRecipe: false);
        s.Pearl.OnHandQty = 50;
        await db.SaveChangesAsync();
        await SellAsync(db, s);

        Assert.Equal(48, await OnHandAsync(db, s.Pearl.Id));
        Assert.Equal(1000, await OnHandAsync(db, s.Starch.Id));
    }

    [Fact]
    public async Task Return_restores_topping_materials()
    {
        using var db = NewDb();
        var s = await SeedAsync(db);
        await SellAsync(db, s);

        await PosSaleStockHelper.ApplyToppingReturnAsync(db, StoreId, s.Order, s.Line, 1, "TH0001", "Khách trả", "tester");
        await db.SaveChangesAsync();

        Assert.Equal(1000 - 30, await OnHandAsync(db, s.Starch.Id));
        Assert.Equal(0, await OnHandAsync(db, s.Pearl.Id));
    }

    [Fact]
    public async Task Topping_price_must_match_selling_price_unless_on_prior_draft()
    {
        using var db = NewDb();
        var s = await SeedAsync(db, pearlHasRecipe: false);
        var group = new PosToppingGroup { Id = Guid.NewGuid(), StoreId = StoreId, Name = "Topping", IsActive = true };
        db.PosToppingGroups.Add(group);
        db.PosToppingGroupItems.Add(new PosToppingGroupItem
        {
            Id = Guid.NewGuid(), StoreId = StoreId, GroupId = group.Id, ToppingProductId = s.Pearl.Id, ExtraPrice = 7000, IsActive = true,
        });
        await db.SaveChangesAsync();
        string Json(decimal price) => $$"""[{"id":"{{s.Pearl.Id}}","name":"Trân châu","price":{{price}},"qty":2}]""";

        Assert.True(await PosSalesController.ToppingPricesAllowedAsync(db, StoreId, [Json(5000)], null)); // giá bán topping
        Assert.True(await PosSalesController.ToppingPricesAllowedAsync(db, StoreId, [Json(7000), null], null)); // giá trong nhóm
        Assert.False(await PosSalesController.ToppingPricesAllowedAsync(db, StoreId, [Json(0)], null));
        Assert.False(await PosSalesController.ToppingPricesAllowedAsync(db, StoreId, [Json(3000)], null));
        Assert.True(await PosSalesController.ToppingPricesAllowedAsync(db, StoreId, [Json(3000)], [(s.Pearl.Id, 3000m)]));
        Assert.True(await PosSalesController.ToppingPricesAllowedAsync(db, StoreId, [null, ""], null));
    }

    [Fact]
    public async Task Profit_by_product_puts_topping_material_cost_on_the_topping()
    {
        using var db = NewDb();
        var s = await SeedAsync(db);
        await SellAsync(db, s);

        var cogs = await PosReportMoney.CogsByProductAsync(db, StoreId, [s.Order.Id]);
        Assert.Equal(2 * 30 * 20m, cogs.GetValueOrDefault(s.Pearl.Id)); // 60 g × 20đ
        Assert.Equal(2 * 8000m, cogs.GetValueOrDefault(s.Tea.Id));
        Assert.False(cogs.ContainsKey(s.Starch.Id));
    }
}
