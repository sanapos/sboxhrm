using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

public class PosAiMenuServiceTests
{
    /// <summary>Gemini giả: trả JSON cố định, ghi lại prompt để kiểm tra danh mục mẫu được gửi.</summary>
    sealed class FakeGemini(string json) : IGeminiAiService
    {
        public string? LastPrompt;
        public Task<string> GenerateJsonAsync(string systemPrompt, string userPrompt,
            IReadOnlyList<AiFilePart>? files = null, int maxTokens = 16384, CancellationToken cancellationToken = default)
        {
            LastPrompt = userPrompt;
            return Task.FromResult(json);
        }
        public bool IsConfigured => true;
        public bool IsEnabled => true;
        public Task<AiGeneratedContent> GenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength) => throw new NotSupportedException();
        public IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<string> GeneratePlainTextAsync(string systemPrompt, string userPrompt, int maxTokens = 1024) => throw new NotSupportedException();
        public Task<string> GenerateAssistantChatAsync(string systemPrompt, IReadOnlyList<(string Role, string Content)> messages, int maxTokens = 2048, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<System.Text.Json.JsonElement> GenerateContentRawAsync(object requestBody, CancellationToken cancellationToken = default, string? model = null) => throw new NotSupportedException();
        public void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null) { }
        public GeminiConfig GetCurrentConfig() => new();
    }

    static ZKTecoDbContext NewDb() => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options);

    const string AiJson = """
        {"items":[
          {"name":"Cà phê sữa đá","category":"Cà phê","price":25000,"sizes":[],"unit":"Ly","catalogIndex":0},
          {"name":"Trà sữa trân châu","category":"Trà sữa","price":"30000","sizes":[{"name":"M","price":30000},{"name":"L","price":38000}],"unit":"Ly","catalogIndex":99},
          {"name":"Bánh mì","category":"Ăn nhanh","price":20000,"sizes":[{"name":"Thường","price":20000}],"unit":"Cái","catalogIndex":null},
          {"name":"  ","category":"X","price":1}
        ]}
        """;

    [Fact]
    public async Task Scan_maps_catalog_sizes_and_existing_products()
    {
        using var db = NewDb();
        var storeId = Guid.NewGuid();
        var sample = new PosProductSampleCatalog
        {
            Id = Guid.NewGuid(), Name = "Cà phê sữa đá", CategoryName = "Cà phê",
            ImageUrl = "catalog/pos-samples/cf.jpg", IsActive = true, ProductType = PosProductType.Goods,
        };
        db.Add(sample);
        db.Add(new PosProduct { Id = Guid.NewGuid(), StoreId = storeId, ProductCode = "HH00001", Name = "Banh Mi", IsActive = true });
        await db.SaveChangesAsync();

        var gemini = new FakeGemini(AiJson);
        var result = await new PosAiMenuService(db, gemini).ScanAsync(storeId, [], CancellationToken.None);

        Assert.Contains("0 | Cà phê sữa đá | Cà phê", gemini.LastPrompt);
        Assert.Equal(3, result.Items.Count); // dòng tên trống bị bỏ
        var cf = result.Items[0];
        Assert.Equal(sample.Id, cf.SampleCatalogId);
        Assert.Equal("catalog/pos-samples/cf.jpg", cf.ImageUrl);
        var ts = result.Items[1];
        Assert.Null(ts.SampleCatalogId); // index 99 không tồn tại → bỏ
        Assert.Equal(2, ts.Sizes.Count);
        Assert.Equal(30000, ts.Price);
        var bm = result.Items[2];
        Assert.Empty(bm.Sizes); // một size = món một giá
        Assert.NotNull(bm.ExistingProductId); // "Bánh mì" trùng "Banh Mi" (bỏ dấu)
    }

    [Fact]
    public async Task Import_creates_categories_products_size_variants_and_skips_duplicates()
    {
        using var db = NewDb();
        var storeId = Guid.NewGuid();
        db.Add(new PosProduct { Id = Guid.NewGuid(), StoreId = storeId, ProductCode = "HH00001", Name = "Bánh mì", IsActive = true });
        await db.SaveChangesAsync();

        var items = new List<MenuItemDto>
        {
            new("Trà sữa", "Trà sữa", 30000, [new("M", 30000), new("L", 38000)], "Ly", null, null, null, null, null, null),
            new("Trà đào", "trà sữa", 35000, [], "Ly", null, "catalog/x.jpg", null, null, null, null),
            new("Bánh mì", "Ăn nhanh", 20000, [], "Cái", null, null, null, null, null, null),
        };
        var result = await new PosAiMenuService(db, new FakeGemini("{}"))
            .ImportAsync(storeId, items, "tester", CancellationToken.None);

        Assert.Equal(1, result.CategoriesCreated); // "Trà sữa" / "trà sữa" gộp một nhóm
        Assert.Equal(2, result.ProductsCreated);
        Assert.Equal(2, result.VariantsCreated);
        Assert.Single(result.Skipped);

        var products = await db.PosProducts.Where(p => p.StoreId == storeId).ToListAsync();
        Assert.Equal(3, products.Select(p => p.ProductCode).Distinct().Count());
        var variants = await db.PosProductVariants.ToListAsync();
        Assert.Contains(variants, v => v.AttributeJson == "{\"Size\":\"L\",\"_unit\":\"Ly\",\"_conversion\":\"1\"}" && v.BasePrice == 38000);
        Assert.Equal("catalog/x.jpg", products.Single(p => p.Name == "Trà đào").ImageUrl);
    }

    static MenuItemDto Item(string name, decimal price, List<MenuSizeDto>? sizes = null,
        string? category = null, Guid? sampleId = null) =>
        new(name, category, price, sizes ?? [], null, null, null, sampleId, null, null, null);

    [Fact]
    public void NormalizePrice_single_size_keeps_its_price_when_ai_left_price_zero()
    {
        var (price, sizes) = PosAiMenuService.NormalizePrice(0, [new MenuSizeDto("Ly", 25000)]);
        Assert.Equal(25000, price);
        Assert.Empty(sizes);
    }

    [Fact]
    public void NormalizePrice_size_without_price_does_not_drag_base_price_to_zero()
    {
        var (price, sizes) = PosAiMenuService.NormalizePrice(0,
            [new MenuSizeDto("M", 0), new MenuSizeDto("L", 38000), new MenuSizeDto("S", 30000), new MenuSizeDto("s ", 31000)]);
        Assert.Equal(30000, price);
        Assert.Equal(["M", "L", "S"], sizes.Select(s => s.Name));
    }

    [Fact]
    public async Task Import_uses_type_code_prefix_and_sample_billing_for_services()
    {
        using var db = NewDb();
        var storeId = Guid.NewGuid();
        var karaoke = new PosProductSampleCatalog
        {
            Id = Guid.NewGuid(), Name = "Phòng karaoke VIP", UnitName = "Giờ", IsActive = true,
            ProductType = PosProductType.Service, ServiceBillingMode = PosServiceBillingMode.PerHour,
        };
        var topping = new PosProductSampleCatalog
        {
            Id = Guid.NewGuid(), Name = "Trân châu đen", UnitName = "Phần", IsActive = true, ProductType = PosProductType.Topping,
        };
        db.AddRange(karaoke, topping);
        await db.SaveChangesAsync();

        var result = await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(storeId,
        [
            Item("Phòng VIP", 200000, sampleId: karaoke.Id),
            Item("Trân châu đen", 5000, category: "Topping", sampleId: topping.Id),
            Item("Cà phê sữa", 0, [new MenuSizeDto("M", 0), new MenuSizeDto("L", 35000)], "Cà phê"),
        ], "tester", CancellationToken.None);

        Assert.Equal(3, result.ProductsCreated);
        var products = await db.PosProducts.ToDictionaryAsync(p => p.Name);
        var room = products["Phòng VIP"];
        Assert.Equal(PosProductType.Service, room.ProductType);
        Assert.StartsWith("DV", room.ProductCode);
        Assert.Equal(PosServiceBillingMode.PerHour, room.ServiceBillingMode);
        Assert.Equal("Giờ", room.BaseUnitName);

        var pearl = products["Trân châu đen"];
        Assert.Equal(PosProductType.Topping, pearl.ProductType);
        Assert.StartsWith("TP", pearl.ProductCode);
        Assert.True(pearl.IsTopping);

        var coffee = products["Cà phê sữa"];
        Assert.Equal(PosProductType.Goods, coffee.ProductType);
        Assert.StartsWith("HH", coffee.ProductCode);
        Assert.Equal(35000, coffee.BasePrice);
        var variants = await db.PosProductVariants.Where(v => v.ProductId == coffee.Id).ToListAsync();
        Assert.All(variants, v => Assert.Equal(35000, v.BasePrice)); // size M chưa có giá → lấy giá món
    }

    [Fact]
    public async Task Import_reports_duplicate_in_list_separately_from_existing()
    {
        using var db = NewDb();
        var storeId = Guid.NewGuid();
        db.Add(new PosProduct { Id = Guid.NewGuid(), StoreId = storeId, ProductCode = "HH00001", Name = "Trà đào", IsActive = true });
        await db.SaveChangesAsync();

        var result = await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(storeId,
        [
            Item("Tra dao", 30000),
            Item("Bạc xỉu", 29000, category: "Cà phê phin"),
            Item("Bạc Xỉu", 32000, category: "Cà phê máy"),
        ], "tester", CancellationToken.None);

        Assert.Equal(1, result.ProductsCreated);
        Assert.Equal(["Tra dao (đã có)", "Bạc Xỉu (trùng tên trong danh sách)"], result.Skipped);
        Assert.Equal("HH00002", (await db.PosProducts.SingleAsync(p => p.Name == "Bạc xỉu")).ProductCode);
    }

    const string AiTypedJson = """
        {"items":[
          {"name":"Trà sữa","category":"Trà sữa","price":30000,"type":"goods","unit":"Ly"},
          {"name":"Trân châu trắng","category":"Topping","price":5000,"type":"topping","toppingFor":["Trà sữa"," trà sữa "]},
          {"name":"Phòng VIP","category":"Phòng","price":250000,"type":"service","billing":"hour","unit":"Giờ"},
          {"name":"Gói 10 buổi","category":"Gói tập","price":1800000,"type":"service","billing":"session","sessions":10},
          {"name":"Combo 1","category":"Combo","price":55000,"type":"combo","comboItems":[{"name":"Trà sữa","qty":2},{"name":" "}]},
          {"name":"Cắt tóc nam","category":"Tóc","price":80000}
        ]}
        """;

    [Fact]
    public async Task Scan_reads_ai_type_billing_topping_targets_and_combo_parts()
    {
        using var db = NewDb();
        db.Add(new PosProductSampleCatalog
        {
            Id = Guid.NewGuid(), Name = "Cắt tóc nam", IsActive = true, ProductType = PosProductType.Service,
        });
        await db.SaveChangesAsync();

        var result = await new PosAiMenuService(db, new FakeGemini(AiTypedJson)).ScanAsync(Guid.NewGuid(), [], CancellationToken.None);
        var byName = result.Items.ToDictionary(i => i.Name);

        Assert.Equal("Goods", byName["Trà sữa"].ProductType);
        Assert.Empty(byName["Trà sữa"].ToppingFor!);
        Assert.Equal("Topping", byName["Trân châu trắng"].ProductType);
        Assert.Equal(["Trà sữa"], byName["Trân châu trắng"].ToppingFor!);
        Assert.Equal("PerHour", byName["Phòng VIP"].Billing);
        Assert.Equal("PerSession", byName["Gói 10 buổi"].Billing);
        Assert.Equal(10, byName["Gói 10 buổi"].SessionCount);
        var combo = byName["Combo 1"];
        Assert.Equal("Combo", combo.ProductType);
        Assert.Equal([new MenuComboPartDto("Trà sữa", 2)], combo.ComboItems!);
        Assert.Equal("Service", byName["Cắt tóc nam"].ProductType); // AI không ghi loại → theo món mẫu
        Assert.Equal("Flat", byName["Cắt tóc nam"].Billing);
    }

    [Fact]
    public async Task Import_creates_topping_group_and_links_new_and_existing_items_of_target_category()
    {
        using var db = NewDb();
        var storeId = Guid.NewGuid();
        var milkTeaCat = new PosProductCategory { Id = Guid.NewGuid(), StoreId = storeId, Name = "Trà sữa", IsActive = true };
        var oldTea = new PosProduct
        {
            Id = Guid.NewGuid(), StoreId = storeId, ProductCode = "HH00001", Name = "Trà sữa cũ",
            CategoryId = milkTeaCat.Id, IsActive = true,
        };
        db.AddRange(milkTeaCat, oldTea);
        await db.SaveChangesAsync();

        var result = await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(storeId,
        [
            Item("Trà sữa matcha", 35000, category: "Trà sữa"),
            Item("Cà phê đen", 20000, category: "Cà phê"),
            Item("Trân châu", 5000, category: "Topping") with { ProductType = "Topping", ToppingFor = ["tra sua"] },
            Item("Kem cheese", 10000, category: "Topping") with { ProductType = "Topping", ToppingFor = ["Trà sữa"] },
        ], "tester", CancellationToken.None);

        Assert.Equal(1, result.ToppingGroupsCreated);
        Assert.Equal(2, result.ToppingLinksCreated);
        var group = await db.PosToppingGroups.SingleAsync();
        Assert.Equal("Topping", group.Name);
        var items = await db.PosToppingGroupItems.Where(i => i.GroupId == group.Id).ToListAsync();
        Assert.Equal(2, items.Count);
        Assert.All(items, i => Assert.Null(i.ExtraPrice));

        var products = await db.PosProducts.ToDictionaryAsync(p => p.Name);
        var linked = (await db.PosProductToppingGroupLinks.ToListAsync()).Select(l => l.ProductId).ToHashSet();
        Assert.Equal(new HashSet<Guid> { products["Trà sữa matcha"].Id, oldTea.Id }, linked);
        Assert.True(products["Trà sữa matcha"].AllowToppings);
        Assert.True(products["Trà sữa cũ"].AllowToppings);
        Assert.False(products["Cà phê đen"].AllowToppings);
        Assert.False(products["Trân châu"].IsDirectSale);
        Assert.True(products["Trân châu"].IsTopping);
    }

    [Fact]
    public async Task Import_topping_without_targets_links_all_new_goods()
    {
        using var db = NewDb();
        var result = await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(Guid.NewGuid(),
        [
            Item("Trà đào", 30000, category: "Trà"),
            Item("Bánh flan", 15000, category: "Tráng miệng"),
            Item("Thạch", 5000) with { ProductType = "Topping" },
        ], "tester", CancellationToken.None);

        Assert.Equal(2, result.ToppingLinksCreated);
        Assert.Equal("Topping", (await db.PosToppingGroups.SingleAsync()).Name);
        Assert.Contains(await db.PosProductCategories.ToListAsync(), c => c.Name == "Topping");
    }

    [Fact]
    public async Task Import_combo_links_components_or_falls_back_to_goods()
    {
        using var db = NewDb();
        var result = await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(Guid.NewGuid(),
        [
            Item("Cơm gà", 40000),
            Item("Trà đá", 5000),
            Item("Combo trưa", 42000) with { ProductType = "Combo", ComboItems = [new("Com ga", 1), new("Trà đá", 1), new("Canh", 1)] },
            Item("Set lẩu", 300000) with { ProductType = "Combo", ComboItems = [new("Lẩu thái", 1)] },
        ], "tester", CancellationToken.None);

        Assert.Equal(1, result.CombosCreated);
        var products = await db.PosProducts.ToDictionaryAsync(p => p.Name);
        var combo = products["Combo trưa"];
        Assert.Equal(PosProductType.Combo, combo.ProductType);
        Assert.StartsWith("CB", combo.ProductCode);
        var lines = await db.PosProductComboLines.Where(l => l.ComboProductId == combo.Id).ToListAsync();
        Assert.Equal(new HashSet<Guid> { products["Cơm gà"].Id, products["Trà đá"].Id }, lines.Select(l => l.ComponentProductId).ToHashSet());
        Assert.All(lines, l => Assert.True(l.TrackStock && l.IsActive));
        Assert.Equal(PosProductType.Goods, products["Set lẩu"].ProductType);
        Assert.Contains(result.Warnings!, w => w.Contains("Set lẩu"));
        Assert.Contains(result.Warnings!, w => w.Contains("Canh"));
    }

    [Fact]
    public async Task Import_sizes_all_without_price_use_item_price()
    {
        using var db = NewDb();
        await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(Guid.NewGuid(),
            [Item("Sinh tố", 40000, [new MenuSizeDto("M", 0), new MenuSizeDto("L", 0)])], "tester", CancellationToken.None);
        var p = await db.PosProducts.SingleAsync();
        Assert.Equal(40000, p.BasePrice);
        Assert.All(await db.PosProductVariants.ToListAsync(), v => Assert.Equal(40000, v.BasePrice));
    }

    [Fact]
    public async Task Import_service_billing_from_review_and_zero_price_warning()
    {
        using var db = NewDb();
        var result = await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(Guid.NewGuid(),
        [
            Item("Giờ hát phòng thường", 120000) with { ProductType = "Service", Billing = "PerHour", Unit = "Giờ" },
            Item("Gói 10 buổi", 1500000) with { ProductType = "Service", Billing = "PerSession", SessionCount = 10 },
            Item("Massage body", 0) with { ProductType = "Service" },
        ], "tester", CancellationToken.None);

        var products = await db.PosProducts.ToDictionaryAsync(p => p.Name);
        Assert.Equal(PosServiceBillingMode.PerHour, products["Giờ hát phòng thường"].ServiceBillingMode);
        Assert.Equal(10, products["Gói 10 buổi"].SessionPackCount);
        Assert.Equal(90, products["Gói 10 buổi"].SessionPackValidDays);
        var massage = products["Massage body"];
        Assert.Equal(PosServiceBillingMode.Flat, massage.ServiceBillingMode);
        Assert.Equal("Lần", massage.BaseUnitName);
        Assert.True(massage.IsDirectSale);
        Assert.Equal(["«Massage body»: giá 0đ — nhớ sửa giá trong Hàng hóa."], result.Warnings!);
    }
}
