using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

public class PosAiMenuServiceTests
{
    /// <summary>Gemini giả: trả JSON cố định (hoặc theo hàm), ghi lại prompt để kiểm tra danh mục mẫu được gửi.</summary>
    sealed class FakeGemini : IGeminiAiService
    {
        readonly Func<string, IReadOnlyList<AiFilePart>?, string> _respond;
        public FakeGemini(string json) : this((_, _) => json) { }
        public FakeGemini(Func<string, IReadOnlyList<AiFilePart>?, string> respond) => _respond = respond;

        public string? LastPrompt;
        public readonly List<string> Prompts = [];
        public Task<string> GenerateJsonAsync(string systemPrompt, string userPrompt,
            IReadOnlyList<AiFilePart>? files = null, int maxTokens = 16384, CancellationToken cancellationToken = default)
        {
            lock (Prompts)
            {
                LastPrompt = userPrompt;
                Prompts.Add(userPrompt);
            }
            try
            {
                return Task.FromResult(_respond(userPrompt, files));
            }
            catch (Exception ex)
            {
                return Task.FromException<string>(ex);
            }
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
        var result = await new PosAiMenuService(db, gemini).ScanAsync(storeId, [Img], CancellationToken.None);

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
        // "Bánh mì" khác dấu "Banh Mi" → chỉ cảnh báo «có thể trùng», không coi là đã có.
        Assert.Null(bm.ExistingProductId);
        Assert.Equal("Banh Mi", bm.PossibleDuplicateName);
        Assert.Contains(bm.Warnings!, w => w.Contains("Có thể trùng"));
    }

    static readonly AiFilePart Img = new("image/jpeg", [0xFF, 0xD8, 0xFF, 0x00]);

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

        // "Tra dao" chỉ khác dấu "Trà đào" → vẫn tạo, kèm cảnh báo; "Bạc Xỉu" chỉ khác hoa thường → trùng.
        Assert.Equal(2, result.ProductsCreated);
        Assert.Equal(["Bạc Xỉu (trùng tên trong danh sách)"], result.Skipped);
        Assert.Contains(result.Warnings!, w => w.Contains("«Tra dao»") && w.Contains("Trà đào"));
        Assert.Equal("HH00003", (await db.PosProducts.SingleAsync(p => p.Name == "Bạc xỉu")).ProductCode);
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

        var result = await new PosAiMenuService(db, new FakeGemini(AiTypedJson)).ScanAsync(Guid.NewGuid(), [Img], CancellationToken.None);
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

    // ===== Giá «dễ tính» (mục 1) =====

    [Theory]
    [InlineData("35k", 35000, MenuPriceFlag.None)]
    [InlineData("35 nghìn", 35000, MenuPriceFlag.None)]
    [InlineData("1tr2", 1200000, MenuPriceFlag.None)]
    [InlineData("1,5tr", 1500000, MenuPriceFlag.None)]
    [InlineData("1.2tr", 1200000, MenuPriceFlag.None)]
    [InlineData("2k5", 2500, MenuPriceFlag.None)]
    [InlineData("25.000", 25000, MenuPriceFlag.None)]
    [InlineData("25,000đ", 25000, MenuPriceFlag.None)]
    [InlineData("25.000 VNĐ", 25000, MenuPriceFlag.None)]
    [InlineData("35k/ly", 35000, MenuPriceFlag.None)]
    [InlineData("25.5", 25.5, MenuPriceFlag.None)]
    [InlineData("25-30k", 25000, MenuPriceFlag.Range)]
    [InlineData("25k - 30k", 25000, MenuPriceFlag.Range)]
    [InlineData("25.000 đến 30.000", 25000, MenuPriceFlag.Range)]
    [InlineData("thời giá", 0, MenuPriceFlag.AskPrice)]
    [InlineData("Liên hệ", 0, MenuPriceFlag.AskPrice)]
    public void MenuPriceParser_reads_vietnamese_price_text(string text, double expected, MenuPriceFlag flag)
    {
        var p = MenuPriceParser.Parse(text);
        Assert.Equal((decimal)expected, p.Value);
        Assert.Equal(flag, p.Flag);
    }

    [Fact]
    public void MenuPriceParser_unreadable_and_empty()
    {
        Assert.Equal(MenuPriceFlag.Unreadable, MenuPriceParser.Parse("theo size").Flag);
        Assert.Null(MenuPriceParser.Parse("theo size").Value);
        Assert.Equal(new LenientPrice(null, MenuPriceFlag.None, null), MenuPriceParser.Parse("  "));
    }

    [Fact]
    public async Task Scan_one_bad_price_does_not_break_whole_scan()
    {
        using var db = NewDb();
        const string json = """
            {"items":[
              {"name":"Cà phê đen","price":null},
              {"name":"Cà phê sữa","price":"35k"},
              {"name":"Cá kho tộ","price":"thời giá"},
              {"name":"Bạc xỉu","price":{"value":1}},
              {"name":"Trà đào","price":"25-30k"},
              {"name":"Sinh tố","sizes":[{"name":"M","price":"25.000đ"},{"name":"L","price":null}]},
              {"name":12345,"price":"1tr2"},
              "rác",
              {"name":"Nước cam","price":"30000","catalogIndex":"abc","sessions":"10 buổi"}
            ]}
            """;
        var result = await new PosAiMenuService(db, new FakeGemini(json)).ScanAsync(Guid.NewGuid(), [Img], CancellationToken.None);
        var by = result.Items.ToDictionary(i => i.Name);

        Assert.Equal(8, result.Items.Count);
        Assert.Equal(0, by["Cà phê đen"].Price);
        Assert.Equal(35000, by["Cà phê sữa"].Price);
        Assert.Equal(0, by["Cá kho tộ"].Price);
        Assert.Contains(by["Cá kho tộ"].Warnings!, w => w.Contains("thời giá"));
        Assert.Contains(by["Bạc xỉu"].Warnings!, w => w.Contains("không đọc được"));
        Assert.Equal(25000, by["Trà đào"].Price);
        Assert.Contains(by["Trà đào"].Warnings!, w => w.Contains("dao động"));
        Assert.Equal(25000, by["Sinh tố"].Price);
        Assert.Equal([new MenuSizeDto("M", 25000), new MenuSizeDto("L", 0)], by["Sinh tố"].Sizes);
        Assert.Equal(1200000, by["12345"].Price);
        Assert.Equal(30000, by["Nước cam"].Price);
        Assert.Contains(result.Warnings!, w => w.Contains("1 món AI trả sai định dạng"));
    }

    // ===== Giá thiếu «nghìn» (mục 4) =====

    [Fact]
    public async Task Scan_prices_below_1000_are_multiplied_with_warning_except_material()
    {
        using var db = NewDb();
        const string json = """
            {"items":[
              {"name":"Cà phê","price":35},
              {"name":"Trà tắc","price":"25.5"},
              {"name":"Trà sữa","sizes":[{"name":"M","price":25},{"name":"L","price":30}]},
              {"name":"Đường","price":500,"type":"material"}
            ]}
            """;
        var by = (await new PosAiMenuService(db, new FakeGemini(json)).ScanAsync(Guid.NewGuid(), [Img], CancellationToken.None))
            .Items.ToDictionary(i => i.Name);

        Assert.Equal(35000, by["Cà phê"].Price);
        Assert.Contains(by["Cà phê"].Warnings!, w => w.Contains("35.000") || w.Contains("35,000"));
        Assert.Equal(25500, by["Trà tắc"].Price);
        Assert.Equal([25000m, 30000m], by["Trà sữa"].Sizes.Select(s => s.Price));
        Assert.Equal(500, by["Đường"].Price);
        Assert.Null(by["Đường"].Warnings);
    }

    [Fact]
    public async Task Import_warns_price_below_1000()
    {
        using var db = NewDb();
        var result = await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(Guid.NewGuid(),
            [Item("Trà đá", 5), Item("Muối", 300) with { ProductType = "Material" }], "tester", CancellationToken.None);
        Assert.Single(result.Warnings!, w => w.Contains("«Trà đá»") && w.Contains("dưới 1.000đ"));
    }

    // ===== Món mẫu AI chọn phải khớp tên + hiện giá trị chép từ mẫu (mục 3) =====

    [Fact]
    public async Task Scan_rejects_catalog_index_with_different_name_and_exposes_sample_values()
    {
        using var db = NewDb();
        var beef = new PosProductSampleCatalog
        {
            Id = Guid.NewGuid(), Name = "Bánh mì bò", IsActive = true, SortOrder = 0, ImageUrl = "bo.jpg",
        };
        var coffee = new PosProductSampleCatalog
        {
            Id = Guid.NewGuid(), Name = "Cà phê sữa", IsActive = true, SortOrder = 1, ImageUrl = "cf.jpg",
            DefaultCostPrice = 12000, VatRate = 10, UnitName = "Ly",
        };
        db.AddRange(beef, coffee);
        await db.SaveChangesAsync();

        const string json = """
            {"items":[
              {"name":"Bánh mì bơ","price":20000,"catalogIndex":0},
              {"name":"Cà phê sữa đá","price":29000,"catalogIndex":1}
            ]}
            """;
        var by = (await new PosAiMenuService(db, new FakeGemini(json)).ScanAsync(Guid.NewGuid(), [Img], CancellationToken.None))
            .Items.ToDictionary(i => i.Name);

        Assert.Null(by["Bánh mì bơ"].SampleCatalogId); // AI chọn nhầm «Bánh mì bò» → bỏ
        Assert.Null(by["Bánh mì bơ"].ImageUrl);
        var cf = by["Cà phê sữa đá"];
        Assert.Equal(coffee.Id, cf.SampleCatalogId);
        Assert.Equal("cf.jpg", cf.ImageUrl);
        Assert.Equal(12000, cf.SampleCostPrice);
        Assert.Equal(10, cf.SampleVatRate);
        Assert.Equal("Ly", cf.SampleUnit);
        Assert.Equal("Ly", cf.Unit); // AI không ghi đơn vị → lấy theo mẫu, hiện trên màn xem trước
    }

    [Fact]
    public async Task Import_copies_sample_cost_only_while_linked()
    {
        using var db = NewDb();
        var sample = new PosProductSampleCatalog
        {
            Id = Guid.NewGuid(), Name = "Cà phê sữa", IsActive = true, DefaultCostPrice = 12000, VatRate = 10,
            Description = "Mô tả mẫu",
        };
        db.Add(sample);
        await db.SaveChangesAsync();

        await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(Guid.NewGuid(),
        [
            Item("Cà phê sữa", 29000, sampleId: sample.Id),
            Item("Cà phê sữa đá", 32000), // đã bỏ liên kết mẫu trên màn xem trước
        ], "tester", CancellationToken.None);

        var products = await db.PosProducts.ToDictionaryAsync(p => p.Name);
        Assert.Equal(12000, products["Cà phê sữa"].CostPrice);
        Assert.Equal(10, products["Cà phê sữa"].VatRate);
        Assert.Null(products["Cà phê sữa"].Description); // mô tả mẫu không còn chép ngầm
        Assert.Equal(0, products["Cà phê sữa đá"].CostPrice);
        Assert.Equal(8, products["Cà phê sữa đá"].VatRate);
    }

    [Theory]
    [InlineData("Cà phê sữa đá", "Cà phê sữa", true)]
    [InlineData("Bánh mì bơ", "Bánh mì bò", false)]
    [InlineData("Ca phe sua", "Cà phê sữa", true)]
    [InlineData("Trà", "Trà sữa", false)]
    [InlineData("Trà sữa trân châu đường đen", "Trà sữa trân châu", true)]
    [InlineData("Cà phê đen đá", "Cà phê sữa đá", false)]
    public void SameDish_requires_strong_name_overlap(string a, string b, bool expected) =>
        Assert.Equal(expected, PosProductNameMatch.SameDish(a, b));

    // ===== Trùng tên không bỏ dấu (mục 8) =====

    [Fact]
    public async Task Scan_duplicates_exact_only_diacritic_variant_is_possible_duplicate()
    {
        using var db = NewDb();
        var storeId = Guid.NewGuid();
        db.Add(new PosProduct { Id = Guid.NewGuid(), StoreId = storeId, ProductCode = "HH00001", Name = "Bánh mì bò", IsActive = true });
        await db.SaveChangesAsync();
        const string json = """
            {"items":[
              {"name":"Bánh mì bơ","category":"Bánh mì","price":20000},
              {"name":"bánh  mì BÒ","category":"Bánh mì","price":25000},
              {"name":"Bánh mì bò","category":"Bánh mì","price":25000}
            ]}
            """;
        var items = (await new PosAiMenuService(db, new FakeGemini(json)).ScanAsync(storeId, [Img], CancellationToken.None)).Items;

        Assert.Equal(2, items.Count); // «bánh  mì BÒ» và «Bánh mì bò» là một
        Assert.Null(items[0].ExistingProductId);
        Assert.Equal("Bánh mì bò", items[0].PossibleDuplicateName);
        Assert.NotNull(items[1].ExistingProductId);
    }

    [Fact]
    public async Task Import_keeps_diacritic_variants_apart()
    {
        using var db = NewDb();
        var storeId = Guid.NewGuid();
        db.Add(new PosProduct { Id = Guid.NewGuid(), StoreId = storeId, ProductCode = "HH00001", Name = "Bánh mì bò", IsActive = true });
        await db.SaveChangesAsync();

        var result = await new PosAiMenuService(db, new FakeGemini("{}")).ImportAsync(storeId,
        [
            Item("Bánh mì bơ", 20000),
            Item("BÁNH MÌ BÒ", 25000),
            Item("Bánh mì bò trứng", 30000),
            Item("Combo sáng", 40000) with { ProductType = "Combo", ComboItems = [new("Bánh mì bơ", 1), new("Bánh mì bò", 1)] },
        ], "tester", CancellationToken.None);

        Assert.Equal(["BÁNH MÌ BÒ (đã có)"], result.Skipped);
        Assert.Equal(3, result.ProductsCreated);
        Assert.Contains(result.Warnings!, w => w.Contains("«Bánh mì bơ»") && w.Contains("Bánh mì bò"));
        var products = await db.PosProducts.Where(p => p.StoreId == storeId).ToDictionaryAsync(p => p.Name);
        var lines = await db.PosProductComboLines.Where(l => l.ComboProductId == products["Combo sáng"].Id).ToListAsync();
        // Thành phần ưu tiên tên giống hệt: «Bánh mì bơ» (mới) và «Bánh mì bò» (đã có), không lẫn nhau.
        Assert.Equal(new HashSet<Guid> { products["Bánh mì bơ"].Id, products["Bánh mì bò"].Id },
            lines.Select(l => l.ComponentProductId).ToHashSet());
    }

    // ===== Đọc từng ảnh, gộp, báo ảnh lỗi (mục 2) =====

    [Fact]
    public async Task Scan_each_image_separately_merges_and_reports_failed_image()
    {
        using var db = NewDb();
        var img1 = new AiFilePart("image/jpeg", [1]);
        var img2 = new AiFilePart("image/jpeg", [2]);
        var img3 = new AiFilePart("image/jpeg", [3]);
        var gemini = new FakeGemini((_, files) => files![0].Data[0] switch
        {
            1 => """{"items":[{"name":"Cà phê sữa","category":"Cà phê","price":0},{"name":"Trà đào","price":30000}]}""",
            2 => """{"items":[{"name":"Cà phê sữa","category":"Cà phê","price":29000},{"name":"Bạc xỉu","price":32000}]}""",
            _ => throw new AiApiException(GeminiAiService.QuotaMessage, 429),
        });
        var result = await new PosAiMenuService(db, gemini).ScanAsync(Guid.NewGuid(), [img1, img2, img3], CancellationToken.None);

        Assert.Equal(3, gemini.Prompts.Count);
        Assert.Equal(["Cà phê sữa", "Trà đào", "Bạc xỉu"], result.Items.Select(i => i.Name));
        Assert.Equal(29000, result.Items[0].Price); // trùng giữa 2 ảnh → giữ dòng có giá
        Assert.Equal([2], result.FailedParts!);
        Assert.Contains(result.Warnings!, w => w.StartsWith("Ảnh 3"));
    }

    [Fact]
    public async Task Scan_all_images_failed_throws_first_error()
    {
        using var db = NewDb();
        var gemini = new FakeGemini((_, _) => throw new AiApiException(GeminiAiService.QuotaMessage, 429));
        var ex = await Assert.ThrowsAsync<AiApiException>(() =>
            new PosAiMenuService(db, gemini).ScanAsync(Guid.NewGuid(), [Img, Img], CancellationToken.None));
        Assert.Equal(GeminiAiService.QuotaMessage, ex.Message);
    }

    [Fact]
    public async Task Scan_truncated_output_keeps_complete_items()
    {
        using var db = NewDb();
        const string partial = """{"items":[{"name":"Cà phê","price":20000,"sizes":[{"name":"M","price":20000},{"name":"L","price":25000}]},{"name":"Trà {đào}","price":30000},{"name":"Bạc xỉ""";
        var gemini = new FakeGemini((_, _) => throw new AiOutputTruncatedException("quá dài", partial));
        var result = await new PosAiMenuService(db, gemini).ScanAsync(Guid.NewGuid(), [Img], CancellationToken.None);

        Assert.Equal(["Cà phê", "Trà {đào}"], result.Items.Select(i => i.Name));
        Assert.Contains(result.Warnings!, w => w.Contains("mới lấy được 2 món"));
        Assert.Null(result.FailedParts);
    }

    [Fact]
    public async Task Scan_time_budget_reports_unfinished_parts()
    {
        using var db = NewDb();
        var slow = new SlowGemini();
        var service = new PosAiMenuService(db, slow) { TimeBudget = TimeSpan.FromMilliseconds(300) };
        var result = await service.ScanAsync(Guid.NewGuid(), [new("image/jpeg", [1]), new("image/jpeg", [9])], CancellationToken.None);
        Assert.Single(result.Items);
        Assert.Equal([1], result.FailedParts!);
        Assert.Contains(result.Warnings!, w => w.Contains("quá lâu"));
    }

    /// <summary>Ảnh có byte 9 trả rất chậm (quá thời gian), ảnh khác trả ngay.</summary>
    sealed class SlowGemini : IGeminiAiService
    {
        public async Task<string> GenerateJsonAsync(string systemPrompt, string userPrompt,
            IReadOnlyList<AiFilePart>? files = null, int maxTokens = 16384, CancellationToken cancellationToken = default)
        {
            if (files![0].Data[0] == 9) await Task.Delay(TimeSpan.FromSeconds(30), cancellationToken);
            return """{"items":[{"name":"Cà phê","price":20000}]}""";
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

    // ===== Lọc catalog mẫu theo ngành (mục 9) =====

    [Fact]
    public async Task Scan_catalog_prompt_filtered_by_store_sell_profile()
    {
        using var db = NewDb();
        var storeId = Guid.NewGuid();
        db.Add(new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = storeId, SellProfile = PosSellProfile.Salon });
        db.AddRange(
            new PosProductSampleCatalog { Id = Guid.NewGuid(), Name = "Trà sữa", IsActive = true, SellProfiles = "Restaurant", Kind = PosProductSampleKind.Drink },
            new PosProductSampleCatalog { Id = Guid.NewGuid(), Name = "Gội đầu", IsActive = true, SellProfiles = "Salon", ProductType = PosProductType.Service },
            new PosProductSampleCatalog { Id = Guid.NewGuid(), Name = "Nước suối", IsActive = true, Kind = PosProductSampleKind.Drink });
        await db.SaveChangesAsync();

        var gemini = new FakeGemini("""{"items":[{"name":"Gội đầu","price":50000}]}""");
        var result = await new PosAiMenuService(db, gemini).ScanAsync(storeId, [Img], CancellationToken.None);

        Assert.Equal(2, result.CatalogSize);
        Assert.Contains("0 | Gội đầu", gemini.LastPrompt); // ngành dịch vụ: dịch vụ lên trước
        Assert.Contains("1 | Nước suối", gemini.LastPrompt);
        Assert.DoesNotContain("Trà sữa", gemini.LastPrompt);
    }

    // ===== AI đọc bảng tính (mục 6) =====

    [Fact]
    public async Task ScanSheet_sends_tsv_chunks_and_merges_results()
    {
        using var db = NewDb();
        var rows = new List<string> { "Tên món\tGiá" };
        rows.AddRange(Enumerable.Range(1, 200).Select(i => $"Món {i}\t{20000 + i}"));
        var sheet = PosMenuSheetReader.Build([("Menu", rows)]);
        Assert.Equal(2, sheet.Chunks.Count);

        var gemini = new FakeGemini((prompt, files) =>
        {
            Assert.Null(files);
            return prompt.Contains("Món 150")
                ? """{"items":[{"name":"Món 150","price":20150},{"name":"Món 1","price":20001}]}"""
                : """{"items":[{"name":"Món 1","price":20001}]}""";
        });
        var result = await new PosAiMenuService(db, gemini).ScanSheetAsync(Guid.NewGuid(), sheet, CancellationToken.None);

        Assert.Equal(2, gemini.Prompts.Count);
        Assert.All(gemini.Prompts, p => Assert.Contains("BẢNG TÍNH:\n### Sheet: Menu", p));
        Assert.Contains(gemini.Prompts, p => p.Contains("chỉ để hiểu cột") && p.Contains("Tên món\tGiá"));
        Assert.Equal(["Món 1", "Món 150"], result.Items.Select(i => i.Name));
    }
}
