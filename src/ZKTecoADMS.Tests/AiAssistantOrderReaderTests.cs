using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using static ZKTecoADMS.Api.Services.AiAssistantOrderReader;

namespace ZKTecoADMS.Tests;

/// <summary>Trợ lý đọc / dịch đơn hàng từ ảnh, PDF, Excel rồi dựng thẻ xác nhận.</summary>
public class AiAssistantOrderReaderTests
{
    sealed class JsonGemini(string json) : IGeminiAiService
    {
        public IReadOnlyList<AiFilePart>? Files;
        public string Prompt = "";
        public int Calls;

        public Task<string> GenerateJsonAsync(string systemPrompt, string userPrompt, IReadOnlyList<AiFilePart>? files = null, int maxTokens = 16384, CancellationToken cancellationToken = default)
        {
            Calls++;
            Files = files;
            Prompt = userPrompt;
            return Task.FromResult(json);
        }

        public bool IsConfigured => true;
        public bool IsEnabled => true;
        public IAsyncEnumerable<JsonElement> StreamGenerateContentRawAsync(object requestBody, CancellationToken cancellationToken = default, string? model = null) => throw new NotSupportedException();
        public Task<JsonElement> GenerateContentRawAsync(object requestBody, CancellationToken cancellationToken = default, string? model = null) => throw new NotSupportedException();
        public Task<AiGeneratedContent> GenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength) => throw new NotSupportedException();
        public IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<string> GeneratePlainTextAsync(string systemPrompt, string userPrompt, int maxTokens = 1024) => throw new NotSupportedException();
        public Task<string> GenerateAssistantChatAsync(string systemPrompt, IReadOnlyList<(string Role, string Content)> messages, int maxTokens = 2048, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null) { }
        public GeminiConfig GetCurrentConfig() => new();
    }

    static readonly Guid Store = Guid.NewGuid();
    static readonly Guid CfSua = Guid.NewGuid();
    static readonly Guid TraSua = Guid.NewGuid();
    static readonly AiFilePart Photo = new("image/jpeg", [1, 2, 3]);

    static ZKTecoDbContext Db()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.PosProducts.AddRange(
            new PosProduct { Id = CfSua, StoreId = Store, ProductCode = "CF01", Name = "Cà phê sữa đá", BaseUnitName = "Ly", BasePrice = 25000, IsActive = true, ProductType = PosProductType.Goods },
            new PosProduct { Id = TraSua, StoreId = Store, ProductCode = "TS01", Name = "Trà sữa trân châu", BaseUnitName = "Ly", BasePrice = 30000, IsActive = true, ProductType = PosProductType.Goods },
            new PosProduct { Id = Guid.NewGuid(), StoreId = Guid.NewGuid(), ProductCode = "X1", Name = "Bánh flan", BaseUnitName = "Cái", BasePrice = 1, IsActive = true });
        db.PosCustomers.Add(new PosCustomer { Id = Guid.NewGuid(), StoreId = Store, Name = "Chị Lan", Phone = "0912345678" });
        db.SaveChanges();
        return db;
    }

    static AiAssistantActions.Ctx Ctx(bool super = true) => new(Store, Guid.NewGuid(), "Admin",
        new Dictionary<string, ModulePermissionDto>(), super, null, AiAssistantScope.Whole(), "đọc đơn");

    static AiAssistantOrderReader Reader(ZKTecoDbContext db, IGeminiAiService gemini) =>
        new(db, gemini, new AiAssistantActions(db, new MemoryCache(new MemoryCacheOptions()), null!, NullLogger<AiAssistantActions>.Instance));

    static readonly ProductRow[] Catalog =
    [
        new(CfSua, "CF01", "893001", "Cà phê sữa đá", "Ly", 25000),
        new(TraSua, "TS01", null, "Trà sữa trân châu", "Ly", 30000),
        new(Guid.NewGuid(), "TS02", null, "Trà sữa matcha", "Ly", 35000),
    ];

    static RawItem Item(string name, string? code = null, int? index = null, string? source = null) =>
        new(source ?? name, name, code, 1, null, null, index);

    [Fact]
    public void Match_code_barcode_and_exact_name_without_accents()
    {
        Assert.Equal(CfSua, MatchProduct(Item("gì đó", "cf01"), Catalog, 400).Product!.Id);
        Assert.Equal(CfSua, MatchProduct(Item("gì đó", "893001"), Catalog, 400).Product!.Id);
        Assert.Equal(CfSua, MatchProduct(Item("ca phe sua da"), Catalog, 400).Product!.Id);
    }

    [Fact]
    public void Match_uses_ai_index_only_inside_the_list_sent_to_ai()
    {
        Assert.Equal(TraSua, MatchProduct(Item("ts tc", index: 1), Catalog, 400).Product!.Id);
        Assert.Null(MatchProduct(Item("ts tc", index: 1), Catalog, 1).Product);
        Assert.Null(MatchProduct(Item("ts tc", index: 99), Catalog, 400).Product);
    }

    [Fact]
    public void Match_ambiguous_name_does_not_pick_a_product()
    {
        // «Trà sữa» khớp hai hàng — không tự chọn, gợi ý cả hai.
        var m = MatchProduct(Item("Trà sữa"), Catalog, 400);
        Assert.Null(m.Product);
        Assert.Contains("Trà sữa matcha", m.Similar);
        Assert.Contains("Trà sữa trân châu", m.Similar);
    }

    [Fact]
    public void Match_unique_phrase_is_accepted_and_unknown_item_is_not()
    {
        Assert.Equal(TraSua, MatchProduct(Item("Trà sữa trân"), Catalog, 400).Product!.Id);
        Assert.Equal(CfSua, MatchProduct(Item("Cà phê"), Catalog, 400).Product!.Id);
        var none = MatchProduct(Item("Bánh flan"), Catalog, 400);
        Assert.Null(none.Product);
        Assert.Empty(none.Similar);
    }

    [Fact]
    public void Parse_accepts_string_numbers_and_drops_unnamed_lines()
    {
        var r = ParseResult("""
            {"readOnly":true,"warnings":["mờ dòng 2"," "],"orders":[{"kind":"purchase","language":"zh","party":{"name":"NCC A","phone":null},
             "items":[{"source":"奶茶","name":"Trà sữa","qty":"1,5","price":"35k"},{"qty":2},{"name":"Đường","qty":null}]},
             {"kind":"sale","items":[]}]}
            """);
        Assert.True(r.ReadOnly);
        Assert.Equal(["mờ dòng 2"], r.Warnings);
        var o = Assert.Single(r.Orders);
        Assert.True(o.Purchase);
        Assert.Equal("NCC A", o.PartyName);
        Assert.Equal(2, o.Items.Count);
        Assert.Equal(1.5m, o.Items[0].Qty);
        Assert.Equal(35000m, o.Items[0].Price);
        Assert.Null(o.Items[1].Qty);
    }

    [Theory]
    [InlineData("Cà phê sữa đá", "Cà phê sữa đá", "Cà phê sữa đá")]
    [InlineData("Cà phê sữa đá x 3 25k", "Cà phê sữa đá", "Cà phê sữa đá")]   // AI chép cả dòng vào source
    [InlineData("Cà phê sữa đá\t2\t25000", "Cà phê sữa đá", "Cà phê sữa đá")] // ô bảng tính
    [InlineData("珍珠奶茶 (2 ly) 30.000đ / ly", "Trà sữa trân châu", "珍珠奶茶 (Trà sữa trân châu)")]
    [InlineData("冰奶咖啡 x 2", "Cà phê sữa đá", "冰奶咖啡 (Cà phê sữa đá)")]
    [InlineData("cf sữa", "Cà phê sữa", "cf sữa (Cà phê sữa)")]
    [InlineData("7UP lon", "Nước ngọt 7UP", "7UP lon (Nước ngọt 7UP)")]       // số đầu tên hàng không bị cắt
    public void Item_label_shows_only_the_name(string source, string name, string expected) =>
        Assert.Equal(expected, ItemLabel(new RawItem(source, name, null, 1, null, null, null)));

    [Fact]
    public void Parse_accepts_nulls_in_every_field_as_gemini_returns_them()
    {
        // Đúng dạng Gemini trả trên production: mọi trường trống đều là null.
        var r = ParseResult("""
            {"readOnly":false,"warnings":[],"orders":[{"kind":"sale","language":"vi","party":{"name":null,"phone":null},"discount":null,"total":null,"paid":null,"note":null,
             "items":[{"source":"Cà phê","name":"Cà phê","code":null,"qty":null,"unit":null,"price":null,"productIndex":null}]}]}
            """);
        var item = Assert.Single(Assert.Single(r.Orders).Items);
        Assert.Null(item.ProductIndex);
        Assert.Null(item.Qty);
        Assert.Null(item.Price);
    }

    [Fact]
    public async Task Sale_order_becomes_a_draft_card_with_translation_and_unmatched_lines()
    {
        await using var db = Db();
        var gemini = new JsonGemini("""
            {"orders":[{"kind":"sale","language":"zh","party":{"name":"Khách X","phone":"+84 912 345 678"},"total":60000,
             "items":[{"source":"冰奶咖啡","name":"Cà phê sữa đá","qty":2},{"source":"布丁","name":"Bánh flan","qty":1},{"source":"?","name":"Trà sữa trân châu","qty":null}]}]}
            """);
        var r = await Reader(db, gemini).ReadAsync(Ctx(), [Photo], null, "giao chiều nay", default);

        Assert.Equal(1, gemini.Calls);
        Assert.Same(Photo, Assert.Single(gemini.Files!));
        Assert.Contains("giao chiều nay", gemini.Prompt);
        Assert.Contains("Cà phê sữa đá", gemini.Prompt);
        Assert.DoesNotContain("Bánh flan", gemini.Prompt); // hàng cửa hàng khác không lọt vào prompt

        var card = Assert.Single(r.Proposed);
        Assert.Equal("sale_draft", card.Kind);
        Assert.Contains("đã dịch sang tiếng Việt", r.Reply);
        Assert.Contains("冰奶咖啡 (Cà phê sữa đá)", r.Reply);
        Assert.Contains("chưa có trong danh mục hàng", r.Reply);
        Assert.Contains("chưa đọc rõ số lượng", r.Reply);
        Assert.Contains(card.Warnings, w => w.Contains("2 dòng"));
        // Khớp khách theo SĐT dù khác cách viết, và chỉ một dòng đủ điều kiện vào phiếu.
        using var body = JsonDocument.Parse(card.Body!);
        Assert.Equal("Chị Lan", body.RootElement.GetProperty("customerName").GetString());
        Assert.Equal(1, body.RootElement.GetProperty("lines").GetArrayLength());
        Assert.False(body.RootElement.GetProperty("complete").GetBoolean());
    }

    [Fact]
    public async Task Paid_order_is_completed_and_total_mismatch_is_flagged()
    {
        await using var db = Db();
        var r = await Reader(db, new JsonGemini("""
            {"orders":[{"kind":"sale","paid":"full","total":99000,"items":[{"name":"Cà phê sữa đá","qty":2,"price":20000}]}]}
            """)).ReadAsync(Ctx(), [Photo], null, null, default);
        var card = Assert.Single(r.Proposed);
        Assert.Equal("sale", card.Kind);
        Assert.Contains(card.Warnings, w => w.Contains("99.000đ") && w.Contains("40.000đ"));
    }

    [Fact]
    public async Task Purchase_defaults_to_debt_and_flags_unknown_supplier()
    {
        await using var db = Db();
        var r = await Reader(db, new JsonGemini("""
            {"orders":[{"kind":"purchase","party":{"name":"Công ty Mới"},"items":[{"name":"Cà phê sữa đá","qty":10,"price":15000}]}]}
            """)).ReadAsync(Ctx(), [Photo], null, null, default);
        var card = Assert.Single(r.Proposed);
        Assert.Equal("purchase_receipt", card.Kind);
        using var body = JsonDocument.Parse(card.Body!);
        Assert.Equal(0m, body.RootElement.GetProperty("paidAmount").GetDecimal());
        Assert.Contains(card.Warnings, w => w.Contains("Công ty Mới"));
    }

    [Fact]
    public async Task Read_only_request_makes_no_card()
    {
        await using var db = Db();
        var r = await Reader(db, new JsonGemini("""
            {"readOnly":true,"orders":[{"kind":"sale","items":[{"name":"Cà phê sữa đá","qty":1}]}]}
            """)).ReadAsync(Ctx(), [Photo], null, "chỉ dịch thôi", default);
        Assert.Empty(r.Proposed);
        Assert.Contains("Cà phê sữa đá", r.Reply);
    }

    [Fact]
    public async Task No_permission_explains_and_makes_no_card()
    {
        await using var db = Db();
        var r = await Reader(db, new JsonGemini("""
            {"orders":[{"kind":"sale","items":[{"name":"Cà phê sữa đá","qty":1}]}]}
            """)).ReadAsync(Ctx(super: false), [Photo], null, null, default);
        Assert.Empty(r.Proposed);
        Assert.Contains("không có quyền", r.Reply);
    }

    [Fact]
    public async Task Not_an_order_says_so()
    {
        await using var db = Db();
        var r = await Reader(db, new JsonGemini("""{"orders":[]}""")).ReadAsync(Ctx(), [Photo], null, null, default);
        Assert.Empty(r.Proposed);
        Assert.Contains("Không thấy đơn hàng", r.Reply);
    }

    [Fact]
    public async Task Sheet_text_goes_into_the_prompt()
    {
        await using var db = Db();
        var gemini = new JsonGemini("""{"orders":[]}""");
        await Reader(db, gemini).ReadAsync(Ctx(), [], "Tên\tSL\nCà phê\t3", null, default);
        Assert.Contains("BẢNG TÍNH", gemini.Prompt);
        Assert.Contains("Cà phê\t3", gemini.Prompt);
    }
}
