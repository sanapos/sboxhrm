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
        Assert.Contains(variants, v => v.AttributeJson == "{\"Size\":\"L\"}" && v.BasePrice == 38000);
        Assert.Equal("catalog/x.jpg", products.Single(p => p.Name == "Trà đào").ImageUrl);
    }
}
