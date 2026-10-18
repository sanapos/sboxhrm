using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Định lượng theo size, tách giá vốn topping khi trả hàng, gắn nhóm topping hàng loạt,
/// báo cáo Nguyên vật liệu và báo cáo Topping.
/// </summary>
public class PosMaterialToppingReportTests
{
    static readonly Guid StoreId = Guid.NewGuid();

    static ZKTecoDbContext NewDb() => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .Options);

    static PosProduct P(string name, PosProductType type, decimal onHand = 0, decimal price = 0, decimal cost = 0,
        Guid? categoryId = null, bool allowToppings = false) => new()
    {
        Id = Guid.NewGuid(), StoreId = StoreId, ProductCode = name.Replace(" ", "")[..Math.Min(6, name.Replace(" ", "").Length)] + Guid.NewGuid().ToString("N")[..4],
        Name = name, ProductType = type, OnHandQty = onHand, BasePrice = price, CostPrice = cost, IsActive = true,
        IsTopping = type == PosProductType.Topping, CategoryId = categoryId, AllowToppings = allowToppings,
    };

    static PosProductRecipeLine Recipe(PosProduct parent, PosProduct comp, decimal qty, Guid? variantId = null) => new()
    {
        Id = Guid.NewGuid(), StoreId = StoreId, ParentProductId = parent.Id, ComponentProductId = comp.Id,
        Qty = qty, VariantId = variantId, IsActive = true,
    };

    // ---------- Định lượng theo size ----------

    [Fact]
    public void RecipeFor_uses_size_lines_then_falls_back_to_all_sizes()
    {
        var tea = Guid.NewGuid();
        var sizeL = Guid.NewGuid();
        var sizeM = Guid.NewGuid();
        var milk = Guid.NewGuid();
        var pearl = Guid.NewGuid();
        var map = new Dictionary<Guid, List<PosProductRecipeLine>>
        {
            [tea] =
            [
                new() { ParentProductId = tea, ComponentProductId = milk, Qty = 30 },
                new() { ParentProductId = tea, ComponentProductId = pearl, Qty = 20 },
                new() { ParentProductId = tea, ComponentProductId = milk, Qty = 50, VariantId = sizeL },
            ],
        };
        Assert.Equal([30m, 20m], PosSaleStockHelper.RecipeFor(map, tea, sizeM).Select(l => l.Qty));
        Assert.Equal([50m], PosSaleStockHelper.RecipeFor(map, tea, sizeL).Select(l => l.Qty));
        Assert.Equal([30m, 20m], PosSaleStockHelper.RecipeFor(map, tea, null).Select(l => l.Qty));
        Assert.Empty(PosSaleStockHelper.RecipeFor(map, Guid.NewGuid(), sizeL));
    }

    [Fact]
    public async Task Sale_by_size_deducts_size_recipe()
    {
        using var db = NewDb();
        var tea = P("Trà sữa", PosProductType.Goods, price: 30000);
        var milk = P("Sữa tươi", PosProductType.Material, onHand: 1000, cost: 30);
        var m = new PosProductVariant { Id = Guid.NewGuid(), StoreId = StoreId, ProductId = tea.Id, SkuCode = "TS-M", Name = "M", AttributeJson = "{\"Size\":\"M\"}", IsActive = true };
        var l = new PosProductVariant { Id = Guid.NewGuid(), StoreId = StoreId, ProductId = tea.Id, SkuCode = "TS-L", Name = "L", AttributeJson = "{\"Size\":\"L\"}", IsActive = true };
        db.AddRange(tea, milk, m, l, Recipe(tea, milk, 30), Recipe(tea, milk, 50, l.Id));
        var order = new PosSaleOrder { Id = Guid.NewGuid(), StoreId = StoreId, OrderNo = "HD1", IsActive = true };
        db.Add(order);
        await db.SaveChangesAsync();

        var lines = new List<PosSaleOrderLine>
        {
            new() { Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, ProductId = tea.Id, VariantId = m.Id, ProductName = "Trà sữa — M", Qty = 2, IsActive = true },
            new() { Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, ProductId = tea.Id, VariantId = l.Id, ProductName = "Trà sữa — L", Qty = 1, IsActive = true },
        };
        var plan = new SaleStockPlan
        {
            Products = await db.PosProducts.AsTracking().ToDictionaryAsync(p => p.Id),
            Variants = await db.PosProductVariants.AsTracking().ToDictionaryAsync(v => v.Id),
            RecipeLinesMap = (await db.PosProductRecipeLines.ToListAsync()).GroupBy(r => r.ParentProductId).ToDictionary(g => g.Key, g => g.ToList()),
            AllowNegativeStock = true,
        };
        await PosSaleStockHelper.ApplySaleStockAsync(db, StoreId, order, lines, plan, "t");
        await db.SaveChangesAsync();

        Assert.Equal(1000 - 2 * 30 - 1 * 50, (await db.PosProducts.AsNoTracking().SingleAsync(p => p.Id == milk.Id)).OnHandQty);
        Assert.Equal(0, (await db.PosProductVariants.AsNoTracking().SingleAsync(v => v.Id == l.Id)).OnHandQty); // không trừ biến thể
    }

    // ---------- Tách giá vốn topping khi trả hàng ----------

    [Fact]
    public async Task Return_cost_of_topping_is_taken_off_the_topping_not_the_drink()
    {
        using var db = NewDb();
        var tea = P("Trà sữa", PosProductType.Goods, cost: 8000);
        var pearl = P("Trân châu", PosProductType.Topping, cost: 1000);
        var order = new PosSaleOrder { Id = Guid.NewGuid(), StoreId = StoreId, OrderNo = "HD2", IsActive = true };
        db.AddRange(tea, pearl, order,
            new PosSaleOrderLine
            {
                Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, ProductId = tea.Id, ProductName = "Trà sữa", Qty = 2, IsActive = true,
                ToppingsJson = $$"""[{"id":"{{pearl.Id}}","name":"Trân châu","price":5000,"qty":1}]""",
            },
            new PosStockTransaction { Id = Guid.NewGuid(), StoreId = StoreId, ProductId = tea.Id, TransactionType = PosStockTransactionType.Sale, QtyChange = -2, LineAmount = 16000, SaleOrderId = order.Id, Note = "Bán hàng POS", IsActive = true },
            new PosStockTransaction { Id = Guid.NewGuid(), StoreId = StoreId, ProductId = pearl.Id, TransactionType = PosStockTransactionType.Sale, QtyChange = -2, LineAmount = 2000, SaleOrderId = order.Id, Note = "Topping — Trà sữa", IsActive = true },
            new PosSaleReturnLine
            {
                Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, SaleOrderLineId = Guid.NewGuid(), ReturnNo = "TH1",
                ProductId = tea.Id, Qty = 1, CostAmount = 9000, IsActive = true,
                ToppingCostJson = PosSaleReturnLedger.SerializeToppingCost(new Dictionary<Guid, decimal> { [pearl.Id] = 1000 }),
            });
        await db.SaveChangesAsync();

        var cogs = await PosReportMoney.CogsByProductAsync(db, StoreId, [order.Id]);
        Assert.Equal(8000, cogs[tea.Id]); // 16.000 − 8.000 (trước đây −9.000 → 7.000)
        Assert.Equal(1000, cogs[pearl.Id]); // 2.000 − 1.000 (trước đây giữ 2.000)
    }

    [Fact]
    public void Topping_cost_json_round_trips_and_tolerates_bad_data()
    {
        var id = Guid.NewGuid();
        var json = PosSaleReturnLedger.SerializeToppingCost(new Dictionary<Guid, decimal> { [id] = 1234.5m });
        Assert.Equal(1234.5m, PosSaleReturnLedger.ParseToppingCost(json)[id]);
        Assert.Null(PosSaleReturnLedger.SerializeToppingCost(new Dictionary<Guid, decimal>()));
        Assert.Empty(PosSaleReturnLedger.ParseToppingCost("không phải json"));
        Assert.Empty(PosSaleReturnLedger.ParseToppingCost(null));
    }

    // ---------- Gắn nhóm topping hàng loạt ----------

    [Fact]
    public async Task Bulk_links_by_category_and_product_then_unlinks_and_turns_off_toppings()
    {
        using var db = NewDb();
        var catTea = Guid.NewGuid();
        var catCoffee = Guid.NewGuid();
        var a = P("Trà sữa A", PosProductType.Goods, categoryId: catTea);
        var b = P("Trà sữa B", PosProductType.Goods, categoryId: catTea);
        var c = P("Cà phê C", PosProductType.Goods, categoryId: catCoffee);
        var milk = P("Sữa", PosProductType.Material, categoryId: catTea);
        var pearl = P("Trân châu", PosProductType.Topping, categoryId: catTea);
        var group = new PosToppingGroup { Id = Guid.NewGuid(), StoreId = StoreId, Name = "Topping trà sữa", IsActive = true };
        db.AddRange(a, b, c, milk, pearl, group,
            new PosProductToppingOption { Id = Guid.NewGuid(), StoreId = StoreId, ProductId = c.Id, ToppingProductId = pearl.Id, IsActive = true });
        await db.SaveChangesAsync();

        var (added, removed, total) = await PosToppingGroupLinker.SetLinksAsync(db, StoreId, group.Id, [c.Id], [catTea], "t");
        await db.SaveChangesAsync();
        Assert.Equal((3, 0, 3), (added, removed, total)); // A, B (nhóm Trà sữa) + C; không gắn NVL / topping
        Assert.All(await db.PosProducts.Where(p => p.Id == a.Id || p.Id == b.Id || p.Id == c.Id).ToListAsync(), p => Assert.True(p.AllowToppings));
        Assert.Equal(3, (await PosToppingGroupLinker.LinkedProductsAsync(db, StoreId, group.Id)).Count);

        (added, removed, total) = await PosToppingGroupLinker.SetLinksAsync(db, StoreId, group.Id, [a.Id], null, "t");
        await db.SaveChangesAsync();
        Assert.Equal((0, 2, 1), (added, removed, total));
        var products = await db.PosProducts.AsNoTracking().ToDictionaryAsync(p => p.Id);
        Assert.True(products[a.Id].AllowToppings);
        Assert.False(products[b.Id].AllowToppings); // không còn nhóm nào → tắt
        Assert.True(products[c.Id].AllowToppings); // còn tùy chọn thêm riêng → giữ
    }

    // ---------- Báo cáo Nguyên vật liệu ----------

    [Fact]
    public async Task Material_report_uses_recipe_consumption_net_of_cancels_and_flags_running_out()
    {
        using var db = NewDb();
        var now = DateTime.UtcNow;
        var milk = P("Sữa tươi", PosProductType.Material, onHand: 500, cost: 100);
        var starch = P("Bột năng", PosProductType.Material, onHand: 10, cost: 50);
        var coffee = P("Cà phê đá", PosProductType.Goods, onHand: -5);
        var tea = P("Trà sữa", PosProductType.Goods);
        var order = new PosSaleOrder { Id = Guid.NewGuid(), StoreId = StoreId, OrderNo = "HD3", IsActive = true };
        PosStockTransaction Tx(PosProduct p, PosStockTransactionType type, decimal qty, decimal amount, string note) => new()
        {
            Id = Guid.NewGuid(), StoreId = StoreId, ProductId = p.Id, TransactionType = type, QtyChange = qty,
            LineAmount = type == PosStockTransactionType.Sale ? amount : null, UnitCost = 100,
            SaleOrderId = order.Id, Note = note, IsActive = true, CreatedAt = now.AddHours(-2),
        };
        db.AddRange(milk, starch, coffee, tea, order, Recipe(tea, milk, 30), Recipe(tea, starch, 10),
            Tx(milk, PosStockTransactionType.Sale, -300, 30000, "Định lượng: Trà sữa"),
            Tx(milk, PosStockTransactionType.Return, 100, 0, "Hủy đơn: HD3"),
            Tx(starch, PosStockTransactionType.Sale, -70, 3500, "Định lượng: Trân châu"),
            new PosSaleOrderLine { Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, ProductId = coffee.Id, ProductName = coffee.Name, Qty = 12, IsActive = true });
        await db.SaveChangesAsync();

        var r = await PosMaterialReport.BuildAsync(db, StoreId, db.PosStockTransactions, now.AddDays(-7), now, [order.Id]);

        Assert.Equal(7, r.Days);
        var m = r.Materials.Single(x => x.Name == "Sữa tươi");
        Assert.Equal(200, m.UsedQty); // 300 dùng − 100 hoàn khi hủy đơn
        Assert.Equal(20000, m.UsedValue);
        Assert.Equal("green", m.Level);
        Assert.Equal("Trà sữa", Assert.Single(m.Dishes).Name);
        var s = r.Materials.Single(x => x.Name == "Bột năng");
        Assert.Equal(1, s.DaysLeft); // 10 ÷ (70 ÷ 7)
        Assert.Equal("red", s.Level);
        Assert.Equal("Bột năng", r.Materials[0].Name); // đỏ lên đầu
        Assert.Equal("red", r.Verdict);
        Assert.Contains(r.Recommendations, x => x.Title == "Nhập ngay «Bột năng»");
        Assert.Equal("Cà phê đá", Assert.Single(r.NoRecipeDishes).Name);
        Assert.Equal(23500, r.Daily.Sum(d => d.Value));
        Assert.Equal(["Trà sữa", "Trân châu"], r.TopDishes.Select(d => d.Name));
    }

    [Theory]
    [InlineData(0, 0, 5, null, "red")]
    [InlineData(10, 0, 70, 1.0, "red")]
    [InlineData(40, 0, 70, 4.0, "yellow")]
    [InlineData(100, 120, 70, 10.0, "yellow")]
    [InlineData(100, 0, 70, 10.0, "green")]
    [InlineData(100, 0, 0, null, "none")]
    public void Material_level_thresholds(double onHand, double min, double used, double? daysLeft, string level) =>
        Assert.Equal(level, PosMaterialReport.LevelOf((decimal)onHand, (decimal)min, (decimal)used, (decimal?)daysLeft).Level);

    [Fact]
    public void Dish_name_from_stock_notes()
    {
        Assert.Equal("Trà sữa", PosMaterialReport.DishOf("Định lượng: Trà sữa"));
        Assert.Equal("Combo 1", PosMaterialReport.DishOf("Bán combo: Combo 1"));
        Assert.Equal("Trân châu", PosMaterialReport.DishOf("Khách trả — hoàn định lượng: Trân châu"));
        Assert.Equal("Khác", PosMaterialReport.DishOf("Hủy đơn: HD1"));
    }

    // ---------- Báo cáo Topping ----------

    [Fact]
    public async Task Topping_report_counts_cups_with_topping_revenue_and_profit()
    {
        using var db = NewDb();
        var tea = P("Trà sữa", PosProductType.Goods, price: 30000, allowToppings: true);
        var coffee = P("Cà phê", PosProductType.Goods, price: 20000);
        var pearl = P("Trân châu", PosProductType.Topping, onHand: 50, price: 5000, cost: 1000);
        var order = new PosSaleOrder
        {
            Id = Guid.NewGuid(), StoreId = StoreId, OrderNo = "HD4", IsActive = true, Total = 225000,
            Status = PosSaleOrderStatus.Completed, CreatedAt = DateTime.UtcNow,
        };
        db.AddRange(tea, coffee, pearl, order,
            new PosSaleOrderLine
            {
                Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, ProductId = tea.Id, ProductName = "Trà sữa", Qty = 3,
                LineTotal = 105000, IsActive = true,
                ToppingsJson = $$"""[{"id":"{{pearl.Id}}","name":"Trân châu","price":5000,"qty":1}]""",
            },
            new PosSaleOrderLine { Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, ProductId = tea.Id, ProductName = "Trà sữa", Qty = 1, LineTotal = 30000, IsActive = true },
            new PosSaleOrderLine { Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, ProductId = coffee.Id, ProductName = "Cà phê", Qty = 5, LineTotal = 90000, IsActive = true },
            new PosStockTransaction { Id = Guid.NewGuid(), StoreId = StoreId, ProductId = pearl.Id, TransactionType = PosStockTransactionType.Sale, QtyChange = -3, LineAmount = 3000, SaleOrderId = order.Id, Note = "Topping — Trà sữa", IsActive = true });
        await db.SaveChangesAsync();

        var r = await PosToppingReport.BuildAsync(db, StoreId, [order.Id]);

        var dish = Assert.Single(r.Dishes); // cà phê không cho chọn topping → không tính
        Assert.Equal((4m, 3m, 75m), (dish.Cups, dish.CupsWithTopping, dish.RatePct));
        var t = Assert.Single(r.Toppings);
        Assert.Equal((3m, 15000m, 3000m, 12000m), (t.Qty, t.Revenue, t.Cost, t.Profit));
        Assert.Equal("green", t.Level);
        Assert.Equal("green", r.Verdict);
        Assert.StartsWith("75% ly có thêm topping", r.VerdictText);
    }

    [Fact]
    public async Task Topping_report_flags_topping_sold_at_a_loss()
    {
        using var db = NewDb();
        var tea = P("Trà sữa", PosProductType.Goods, allowToppings: true);
        var cheese = P("Kem cheese", PosProductType.Topping, onHand: 20, price: 5000);
        var order = new PosSaleOrder { Id = Guid.NewGuid(), StoreId = StoreId, OrderNo = "HD5", IsActive = true, Total = 35000 };
        db.AddRange(tea, cheese, order,
            new PosSaleOrderLine
            {
                Id = Guid.NewGuid(), StoreId = StoreId, SaleOrderId = order.Id, ProductId = tea.Id, ProductName = "Trà sữa", Qty = 1, LineTotal = 35000, IsActive = true,
                ToppingsJson = $$"""[{"id":"{{cheese.Id}}","name":"Kem cheese","price":5000,"qty":1}]""",
            },
            new PosStockTransaction { Id = Guid.NewGuid(), StoreId = StoreId, ProductId = cheese.Id, TransactionType = PosStockTransactionType.Sale, QtyChange = -1, LineAmount = 7000, SaleOrderId = order.Id, Note = "Topping — Trà sữa", IsActive = true });
        await db.SaveChangesAsync();

        var r = await PosToppingReport.BuildAsync(db, StoreId, [order.Id]);
        Assert.Equal("red", r.Verdict);
        Assert.Equal("Bán lỗ: giá vốn cao hơn giá bán", Assert.Single(r.Toppings).Note);
        Assert.Contains(r.Recommendations, x => x.Title == "Chỉnh giá «Kem cheese»");
    }

    [Theory]
    [InlineData(45, "green")]
    [InlineData(30, "green")]
    [InlineData(20, "yellow")]
    [InlineData(5, "red")]
    public void Topping_rate_thresholds(double rate, string level) =>
        Assert.Equal(level, PosToppingReport.RateLevel((decimal)rate));
}
