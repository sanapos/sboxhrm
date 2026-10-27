using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>«Chụp hóa đơn NCC → phiếu nhập»: đọc số dễ tính, đối chiếu hàng / ĐVT / NCC, cảnh báo cộng tổng, tạo phiếu.</summary>
public class PosAiInvoiceServiceTests
{
    /// <summary>Gemini giả: trả JSON cố định theo thứ tự gọi (mỗi ảnh một lần).</summary>
    sealed class FakeGemini(params string[] responses) : IGeminiAiService
    {
        int _call;
        public Task<string> GenerateJsonAsync(string systemPrompt, string userPrompt,
            IReadOnlyList<AiFilePart>? files = null, int maxTokens = 16384, CancellationToken cancellationToken = default)
        {
            var i = Interlocked.Increment(ref _call) - 1;
            return Task.FromResult(responses[Math.Min(i, responses.Length - 1)]);
        }
        public bool IsConfigured => true;
        public bool IsEnabled => true;
        public Task<AiGeneratedContent> GenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength) => throw new NotSupportedException();
        public IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<string> GeneratePlainTextAsync(string systemPrompt, string userPrompt, int maxTokens = 1024) => throw new NotSupportedException();
        public Task<string> GenerateAssistantChatAsync(string systemPrompt, IReadOnlyList<(string Role, string Content)> messages, int maxTokens = 2048, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<JsonElement> GenerateContentRawAsync(object requestBody, CancellationToken cancellationToken = default, string? model = null) => throw new NotSupportedException();
        public void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null) { }
        public GeminiConfig GetCurrentConfig() => new();
    }

    // Cùng cấu hình theo dõi như production: mặc định NoTracking.
    static ZKTecoDbContext NewDb(string? name = null) => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(name ?? Guid.NewGuid().ToString())
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options);

    static readonly AiFilePart Img = new("image/jpeg", [0xFF, 0xD8, 0xFF, 0x00]);
    static readonly Guid Store = Guid.NewGuid();

    static InvoiceProductCandidate Tiger => new(Guid.NewGuid(), "Bia Tiger lon 330ml", "HH00001", "8934822101336", "Lon",
    [
        new(Guid.NewGuid(), "Lon", 1, true, null),
        new(Guid.NewGuid(), "Thùng", 24, false, "8934822191337"),
    ]);

    static InvoiceProductCandidate Product(string name, string unit = "Cái") =>
        new(Guid.NewGuid(), name, "HH" + Random.Shared.Next(10000, 99999), null, unit, [new(Guid.NewGuid(), unit, 1, true, null)]);

    // ─────────────── Đọc JSON ───────────────

    [Fact]
    public void Parse_lenient_numbers_vat_dates_and_missing_fields()
    {
        var inv = PosAiInvoiceParsing.Parse("""
            {"supplier":{"name":"Công ty TNHH Bia Sài Gòn","phone":"0909 123 456","taxCode":"0301234567"},
             "invoiceNo":"0001234","invoiceDate":"Ngày 05 tháng 03 năm 2026","pricesIncludeVat":"false","vatRate":"8%",
             "subtotal":"1.234.567đ","discount":"(10.000)","vat":null,"total":"1.322.333",
             "lines":[
               {"name":"Bia Tiger","qty":"2,5","unit":"Thùng","unitPrice":"350.000","lineTotal":"875.000đ","vatRate":"10%"},
               {"name":"Nước suối","qty":"1.000","unit":"chai","unitPrice":3500,"vatRate":"KCT"},
               {"name":"Đường","qty":null,"unitPrice":null,"lineTotal":"50k","vatRate":0.05,"unreadable":true},
               "rác",
               {"name":"Muối","qty":"3 gói","discountPercent":"10%","vatRate":"x"}
             ]}
            """);
        Assert.Equal("Công ty TNHH Bia Sài Gòn", inv.SupplierName);
        Assert.Equal("0301234567", inv.SupplierTaxCode);
        Assert.Equal(new DateTime(2026, 3, 5), inv.InvoiceDate);
        Assert.False(inv.PricesIncludeVat);
        Assert.Equal(8, inv.Vat.Rate);
        Assert.Equal(1234567, inv.Subtotal.Value);
        Assert.Equal(10000, inv.Discount.Value); // ngoặc = số âm in trên hóa đơn → lấy trị tuyệt đối
        Assert.Null(inv.VatAmount.Value);
        Assert.Equal(1322333, inv.Total.Value);
        Assert.Equal(4, inv.Lines.Count);
        Assert.Equal(1, inv.BadLines); // phần tử "rác"

        Assert.Equal(2.5m, inv.Lines[0].Qty);
        Assert.Equal(350000, inv.Lines[0].UnitPrice.Value);
        Assert.Equal(875000, inv.Lines[0].LineTotal.Value);
        Assert.Equal(10, inv.Lines[0].Vat.Rate);
        Assert.Equal(1000, inv.Lines[1].Qty); // «1.000» = một nghìn
        Assert.True(inv.Lines[1].Vat.Exempt);
        Assert.Null(inv.Lines[2].Qty);
        Assert.Equal(50000, inv.Lines[2].LineTotal.Value);
        Assert.Equal(5, inv.Lines[2].Vat.Rate); // 0,05 → 5%
        Assert.True(inv.Lines[2].Unreadable);
        Assert.Equal(3, inv.Lines[3].Qty);
        Assert.Equal(10, inv.Lines[3].DiscountPercent);
        Assert.False(inv.Lines[3].Vat.HasValue);
    }

    [Theory]
    [InlineData("12/03/2026", 2026, 3, 12)]
    [InlineData("1-3-26", 2026, 3, 1)]
    [InlineData("2026-03-12", 2026, 3, 12)]
    [InlineData("Ngày 31 tháng 12 năm 2025", 2025, 12, 31)]
    public void ParseDate_vietnamese_formats(string text, int y, int m, int d) =>
        Assert.Equal(new DateTime(y, m, d), PosAiInvoiceParsing.ParseDate(text));

    [Theory]
    [InlineData("31/02/2026")]
    [InlineData("không rõ")]
    [InlineData("")]
    public void ParseDate_invalid_is_null(string text) => Assert.Null(PosAiInvoiceParsing.ParseDate(text));

    [Fact]
    public void Salvage_truncated_json_keeps_header_and_complete_lines()
    {
        var inv = PosAiInvoiceParsing.Salvage(
            """{"supplier":{"name":"NCC A"},"invoiceNo":"77","lines":[{"name":"Gạo","qty":2,"unitPrice":20000},{"name":"Mắm","qty":""");
        Assert.Equal("NCC A", inv.SupplierName);
        Assert.Equal("77", inv.InvoiceNo);
        Assert.Single(inv.Lines);
        Assert.Equal("Gạo", inv.Lines[0].Name);
    }

    // ─────────────── Dòng hàng / cảnh báo ───────────────

    static RawInvoiceLine Raw(string name, decimal? qty, decimal? price, decimal? total, string? unit = null) => new()
    {
        Name = name, Qty = qty, Unit = unit,
        UnitPrice = new(price, MenuPriceFlag.None, null),
        LineTotal = new(total, MenuPriceFlag.None, null),
    };

    [Fact]
    public void BuildLine_warns_when_qty_times_price_differs_from_line_total()
    {
        var p = Product("Gạo ST25", "Kg");
        var line = PosAiInvoiceService.BuildLine(Raw("Gạo ST25", 10, 25000, 200000, "kg"), InvoiceVatValue.None, null, [p], [])!;
        Assert.Equal(p.Id, line.MatchedProductId);
        Assert.Equal("name", line.MatchedBy);
        Assert.Equal(200000, line.LineTotal); // giữ thành tiền in trên hóa đơn
        Assert.Contains(line.Warnings, w => w.Contains("khác thành tiền"));

        var ok = PosAiInvoiceService.BuildLine(Raw("Gạo ST25", 10, 25000, 250000, "kg"), InvoiceVatValue.None, null, [p], [])!;
        Assert.DoesNotContain(ok.Warnings, w => w.Contains("khác thành tiền"));
        Assert.Equal("base", ok.UnitStatus);
    }

    [Fact]
    public void BuildLine_derives_missing_qty_and_price()
    {
        var noQty = PosAiInvoiceService.BuildLine(Raw("Đường", null, 20000, 100000), InvoiceVatValue.None, null, [], [])!;
        Assert.Equal(5, noQty.Qty);
        Assert.Contains(noQty.Warnings, w => w.Contains("Không đọc được số lượng"));
        Assert.Null(noQty.MatchedProductId);
        Assert.Equal("none", noQty.UnitStatus);

        var noPrice = PosAiInvoiceService.BuildLine(Raw("Đường", 4, null, 100000), new InvoiceVatValue(8, false), null, [], [])!;
        Assert.Equal(25000, noPrice.UnitPrice);
        Assert.Equal(8, noPrice.VatRate); // thuế suất chung của hóa đơn
        Assert.Contains(noPrice.Warnings, w => w.Contains("Không đọc được đơn giá"));

        Assert.Null(PosAiInvoiceService.BuildLine(Raw("", null, null, null), InvoiceVatValue.None, null, [], []));
    }

    // ─────────────── Đối chiếu ───────────────

    [Fact]
    public void Match_exact_name_then_barcode_then_fuzzy_with_suggestions()
    {
        var tiger = Tiger;
        var coca = Product("Coca Cola lon 320ml", "Lon");
        var pepsi = Product("Pepsi lon 320ml", "Lon");
        var all = new[] { tiger, coca, pepsi };

        Assert.Equal(("name", (Guid?)tiger.Id), Pick(PosAiInvoiceMatching.MatchProduct("bia tiger  LON 330ml", null, null, all, [])));
        // Mã vạch thùng in trên hóa đơn → đúng hàng.
        Assert.Equal(("barcode", (Guid?)tiger.Id), Pick(PosAiInvoiceMatching.MatchProduct("Tiger Crystal??", "8934822191337", null, all, [])));
        Assert.Equal(("fuzzy", (Guid?)coca.Id), Pick(PosAiInvoiceMatching.MatchProduct("Nước ngọt Coca Cola lon 320ml (thùng 24)", null, null, all, [])));

        var none = PosAiInvoiceMatching.MatchProduct("Nước ngọt Pepsi lon 330ml", null, null, all, []);
        Assert.Null(none.Product);
        Assert.InRange(none.Possible.Count, 1, 3);

        static (string?, Guid?) Pick(InvoiceProductMatch m) => (m.By, m.Product?.Id);
    }

    [Fact]
    public void Unit_conversion_uses_declared_unit_and_flags_unknown_unit()
    {
        var tiger = Tiger;
        var thung = PosAiInvoiceMatching.ResolveUnit(tiger, "thung");
        Assert.Equal(("unit", "Thùng", 24m), (thung.Status, thung.UnitName, thung.Factor));
        Assert.Equal("base", PosAiInvoiceMatching.ResolveUnit(tiger, "LON").Status);
        Assert.Equal("base", PosAiInvoiceMatching.ResolveUnit(tiger, null).Status);
        Assert.Equal("unknown", PosAiInvoiceMatching.ResolveUnit(tiger, "Két").Status);

        var line = PosAiInvoiceService.BuildLine(Raw("Bia Tiger lon 330ml", 2, 360000, 720000, "Thùng"),
            InvoiceVatValue.None, null, [tiger], [])!;
        Assert.Equal(24, line.UnitFactor);
        Assert.Equal(48, line.BaseQty);
        Assert.Equal("Thùng", line.UnitName);
        Assert.Contains(line.Warnings, w => w.Contains("1 Thùng = 24 Lon"));

        var ket = PosAiInvoiceService.BuildLine(Raw("Bia Tiger lon 330ml", 2, 360000, 720000, "Két"),
            InvoiceVatValue.None, null, [tiger], [])!;
        Assert.Equal("unknown", ket.UnitStatus);
        Assert.Contains(ket.Warnings, w => w.Contains("chưa có ĐVT «Két»"));
    }

    [Fact]
    public void Remembered_mapping_wins_and_supplies_unit_factor()
    {
        var supplier = Guid.NewGuid();
        var duong = Product("Đường cát trắng Biên Hòa", "Kg");
        var other = Product("Đường phèn", "Kg");
        var mappings = new List<InvoiceMappingCandidate>
        {
            new(supplier, PosProductNameMatch.FoldKey("ĐƯỜNG RE BH 50KG"), duong.Id, "Bao", "Kg", 50),
            new(null, PosProductNameMatch.FoldKey("Đường phèn"), duong.Id, null, null, 1),
        };
        var m = PosAiInvoiceMatching.MatchProduct("Đường RE BH 50kg", null, supplier, [duong, other], mappings);
        Assert.Equal("remembered", m.By);
        Assert.Equal(duong.Id, m.Product!.Id);
        var unit = PosAiInvoiceMatching.ResolveUnit(duong, "bao", m.Mapping);
        Assert.Equal(("remembered", 50m), (unit.Status, unit.Factor));

        // Ánh xạ của NCC khác không áp dụng.
        Assert.NotEqual("remembered", PosAiInvoiceMatching.MatchProduct("Đường RE BH 50kg", null, Guid.NewGuid(), [duong, other], mappings).By);
        // Ánh xạ chung cả cửa hàng (không NCC) thắng cả trùng tên hệt.
        Assert.Equal(duong.Id, PosAiInvoiceMatching.MatchProduct("Đường phèn", null, null, [duong, other], mappings).Product!.Id);
    }

    [Fact]
    public void Supplier_match_by_tax_code_phone_and_name()
    {
        var a = new InvoiceSupplierCandidate(Guid.NewGuid(), "Bia Sài Gòn", "Công ty CP Bia Sài Gòn", "0909123456", "0301234567");
        var b = new InvoiceSupplierCandidate(Guid.NewGuid(), "Đại lý Thành Công", null, "02838000111", null);
        var list = new[] { a, b };
        Assert.Equal(((Guid?)a.Id, "taxCode"), Pick(PosAiInvoiceMatching.MatchSupplier("X", null, "0301-234-567", list)));
        Assert.Equal(((Guid?)b.Id, "phone"), Pick(PosAiInvoiceMatching.MatchSupplier("Y", "+84 283 800 0111", null, list)));
        Assert.Equal(((Guid?)a.Id, "name"), Pick(PosAiInvoiceMatching.MatchSupplier("CÔNG TY TNHH BIA SÀI GÒN", null, null, list)));
        Assert.Equal(((Guid?)b.Id, "name"), Pick(PosAiInvoiceMatching.MatchSupplier("Đại lý Thành Công", null, null, list)));
        Assert.Null(PosAiInvoiceMatching.MatchSupplier("Công ty TNHH Thực phẩm Á Châu", "0123", null, list).Supplier);

        static (Guid?, string?) Pick((InvoiceSupplierCandidate? S, string? By) r) => (r.S?.Id, r.By);
    }

    // ─────────────── Tổng ───────────────

    [Fact]
    public void Totals_warn_when_lines_do_not_add_up()
    {
        var lines = new List<InvoiceLineDto>
        {
            PosAiInvoiceService.BuildLine(Raw("A", 2, 50000, 100000), new(10, false), null, [], [])!,
            PosAiInvoiceService.BuildLine(Raw("B", 1, 200000, 200000), new(10, false), null, [], [])!,
        };
        var ok = new RawInvoice
        {
            Vat = new(10, false),
            Subtotal = new(300000, MenuPriceFlag.None, null),
            VatAmount = new(30000, MenuPriceFlag.None, null),
            Total = new(330000, MenuPriceFlag.None, null),
        };
        var w1 = new List<string>();
        var t = PosAiInvoiceService.CheckTotals(ok, lines, includeVat: false, w1);
        Assert.Empty(w1);
        Assert.Equal(300000, t.LinesSubtotal);
        Assert.Equal(30000, t.LinesVat);
        Assert.Equal(330000, t.LinesTotal);

        var bad = new RawInvoice
        {
            Subtotal = new(350000, MenuPriceFlag.None, null),
            Total = new(400000, MenuPriceFlag.None, null),
        };
        var w2 = new List<string>();
        PosAiInvoiceService.CheckTotals(bad, lines, includeVat: false, w2);
        Assert.Contains(w2, w => w.Contains("Cộng các dòng"));
        Assert.Contains(w2, w => w.Contains("Tổng cộng thanh toán"));
    }

    // ─────────────── Quét + xác nhận (CSDL in-memory) ───────────────

    static async Task<(Guid SupplierId, Guid TigerId, Guid CocaId)> SeedAsync(ZKTecoDbContext db)
    {
        var sup = new PosSupplier
        {
            Id = Guid.NewGuid(), StoreId = Store, SupplierCode = "NCC0001", Name = "Bia Sài Gòn",
            TaxCode = "0301234567", IsActive = true,
        };
        var tiger = new PosProduct
        {
            Id = Guid.NewGuid(), StoreId = Store, ProductCode = "HH00001", Name = "Bia Tiger lon 330ml",
            BaseUnitName = "Lon", ProductType = PosProductType.Goods, IsActive = true, VatRate = 10,
        };
        var coca = new PosProduct
        {
            Id = Guid.NewGuid(), StoreId = Store, ProductCode = "HH00002", Name = "Coca Cola lon",
            BaseUnitName = "Lon", ProductType = PosProductType.Goods, IsActive = true,
        };
        db.AddRange(sup, tiger, coca);
        db.PosProductUnits.AddRange(
            new PosProductUnit { Id = Guid.NewGuid(), StoreId = Store, ProductId = tiger.Id, UnitName = "Lon", ConversionRate = 1, IsBaseUnit = true, IsActive = true },
            new PosProductUnit { Id = Guid.NewGuid(), StoreId = Store, ProductId = tiger.Id, UnitName = "Thùng", ConversionRate = 24, IsActive = true },
            new PosProductUnit { Id = Guid.NewGuid(), StoreId = Store, ProductId = coca.Id, UnitName = "Lon", ConversionRate = 1, IsBaseUnit = true, IsActive = true });
        await db.SaveChangesAsync();
        return (sup.Id, tiger.Id, coca.Id);
    }

    const string Page1 = """
        {"supplier":{"name":"CÔNG TY TNHH BIA SÀI GÒN","taxCode":"0301 234 567"},"invoiceNo":"0000123","invoiceDate":"05/03/2026",
         "pricesIncludeVat":false,"vatRate":"10%",
         "lines":[{"name":"Bia Tiger lon 330ml","qty":2,"unit":"Thùng","unitPrice":"360.000","lineTotal":"720.000"},
                  {"name":"COCA LON 320","qty":"24","unit":"lon","unitPrice":8000,"lineTotal":192000}]}
        """;
    const string Page2 = """
        {"supplier":{"name":null},"lines":[{"name":"Snack khoai tây Poca","qty":10,"unit":"Gói","unitPrice":"5.000","lineTotal":"50.000"}],
         "subtotal":"962.000","vat":"96.200","total":"1.058.200"}
        """;

    [Fact]
    public async Task Scan_merges_pages_matches_supplier_products_and_units()
    {
        await using var db = NewDb();
        var (supId, tigerId, _) = await SeedAsync(db);
        var svc = new PosAiInvoiceService(db, new FakeGemini(Page1, Page2));
        var r = await svc.ScanAsync(Store, [Img, Img], CancellationToken.None);

        Assert.Equal(supId, r.Supplier.MatchedSupplierId);
        Assert.Equal("taxCode", r.Supplier.MatchedBy);
        Assert.Equal("0000123", r.InvoiceNo);
        Assert.Equal(new DateTime(2026, 3, 5), r.InvoiceDate);
        Assert.Equal(3, r.Lines.Count);
        var tiger = r.Lines[0];
        Assert.Equal(tigerId, tiger.MatchedProductId);
        Assert.Equal(("unit", 24m, 48m), (tiger.UnitStatus, tiger.UnitFactor, tiger.BaseQty));
        Assert.Equal(10, tiger.VatRate);
        Assert.Null(r.Lines[1].MatchedProductId); // «COCA LON 320» chưa đủ giống → gợi ý
        Assert.Contains(r.Lines[1].PossibleMatches, p => p.Name == "Coca Cola lon");
        Assert.Equal(1, r.Lines[2].Page);
        Assert.Equal(962000, r.Totals.Subtotal);
        Assert.Equal(962000, r.Totals.LinesSubtotal);
        Assert.Equal(1058200, r.Totals.Total);
        Assert.True(r.Warnings == null || !r.Warnings.Any(w => w.Contains("khác")));
    }

    static InvoiceConfirmRequest Request(Guid? supplierId, Guid tigerId, Guid cocaId, bool complete, decimal paid = 0) => new(
        supplierId, false, null, null, null, null, "0000123", new DateTime(2026, 3, 5), 0, complete, paid, "Tiền mặt", null,
        [
            new("Bia Tiger lon 330ml", tigerId, false, null, 2, "Thùng", 360000, 0, 10, false, false, 24, true, "Thùng"),
            new("COCA LON 320", cocaId, false, null, 1, "Két", 192000, 0, 10, false, false, 24, true, "Két"),
            new("Snack khoai tây Poca", null, true, null, 10, "Gói", 5000, 0, 10, false, false),
        ]);

    [Fact]
    public async Task Confirm_creates_draft_receipt_new_product_and_remembers_mapping()
    {
        var name = Guid.NewGuid().ToString();
        Guid supId, tigerId, cocaId, receiptId;
        await using (var db = NewDb(name))
        {
            (supId, tigerId, cocaId) = await SeedAsync(db);
        }
        await using (var db = NewDb(name))
        {
            var (res, err) = await new PosAiInvoiceService(db, new FakeGemini("{}")).ConfirmAsync(
                Store, null, "owner@test.local", () => Guid.NewGuid(), Request(supId, tigerId, cocaId, complete: false),
                CancellationToken.None);
            Assert.Null(err);
            Assert.Equal("Draft", res!.Status);
            Assert.Equal(1, res.ProductsCreated);
            Assert.Equal(3, res.MappingsSaved);
            receiptId = res.ReceiptId;
        }

        await using (var check = NewDb(name))
        {
            var receipt = await check.PosStockReceipts.Include(x => x.Lines).SingleAsync(x => x.Id == receiptId);
            Assert.Equal(PosPurchaseReceiptStatus.Draft, receipt.Status);
            Assert.Equal(supId, receipt.SupplierId);
            Assert.Equal("0000123", receipt.InputInvoiceNo);
            Assert.Contains("05/03/2026", receipt.Note);
            Assert.Equal(3, receipt.Lines.Count);

            // Thùng đã khai báo → giữ ĐVT hóa đơn (phiếu tự quy đổi tồn khi nhập kho).
            var tiger = receipt.Lines.Single(l => l.ProductId == tigerId);
            Assert.Equal(("Thùng", 2m, 360000m, 720000m, 72000m), (tiger.UnitName, tiger.Qty, tiger.CostPrice, tiger.LineTotal, tiger.VatAmount));
            // «Két» chưa khai báo + hệ số 24 → quy về ĐVT gốc.
            var coca = receipt.Lines.Single(l => l.ProductId == cocaId);
            Assert.Equal(("Lon", 24m, 8000m, 192000m), (coca.UnitName, coca.Qty, coca.CostPrice, coca.LineTotal));
            Assert.Contains("× 24", coca.LineNote);
            var snack = receipt.Lines.Single(l => l.ProductName == "Snack khoai tây Poca");
            Assert.Equal(("Gói", 10m, 5000m), (snack.UnitName, snack.Qty, snack.CostPrice));
            Assert.Equal(962000, receipt.TotalCost);
            Assert.Equal(96200, receipt.TotalVat);

            // Phiếu tạm: chưa cộng kho, chưa ghi nợ NCC.
            Assert.Equal(0, (await check.PosProducts.SingleAsync(p => p.Id == tigerId)).OnHandQty);
            Assert.Equal(0, (await check.PosSuppliers.SingleAsync(s => s.Id == supId)).CurrentDebt);

            var created = await check.PosProducts.SingleAsync(p => p.Name == "Snack khoai tây Poca");
            Assert.Equal(("Gói", 5000m, PosProductType.Goods, (Guid?)supId), (created.BaseUnitName, created.CostPrice, created.ProductType, created.SupplierId));
            Assert.True(await check.PosProductUnits.AnyAsync(u => u.ProductId == created.Id && u.IsBaseUnit && u.UnitName == "Gói"));

            var maps = await check.PosAiInvoiceMappings.Where(m => m.StoreId == Store).ToListAsync();
            Assert.Equal(3, maps.Count);
            var cocaMap = maps.Single(m => m.ProductId == cocaId);
            Assert.Equal((supId, "Két", "Lon", 24m), (cocaMap.SupplierId!.Value, cocaMap.InvoiceUnit, cocaMap.UnitName, cocaMap.UnitFactor));
        }

        // Lần quét sau cùng NCC: «COCA LON 320» tự khớp nhờ ánh xạ đã nhớ, «Két» lấy hệ số 24.
        await using (var db = NewDb(name))
        {
            var again = """
                {"supplier":{"taxCode":"0301234567"},"lines":[{"name":"Coca lon 320","qty":1,"unit":"két","unitPrice":192000,"lineTotal":192000}]}
                """;
            var r = await new PosAiInvoiceService(db, new FakeGemini(again)).ScanAsync(Store, [Img], CancellationToken.None);
            var line = Assert.Single(r.Lines);
            Assert.Equal(("remembered", (Guid?)cocaId), (line.MatchedBy, line.MatchedProductId));
            Assert.Equal(("remembered", 24m, 24m), (line.UnitStatus, line.UnitFactor, line.BaseQty));
        }

        // Xác nhận lần hai cập nhật ánh xạ cũ (DbContext NoTracking — phải đọc AsTracking mới lưu).
        await using (var db = NewDb(name))
        {
            var (res, err) = await new PosAiInvoiceService(db, new FakeGemini("{}")).ConfirmAsync(
                Store, null, "owner@test.local", () => Guid.NewGuid(),
                new InvoiceConfirmRequest(supId, false, null, null, null, null, null, null, 0, false, 0, null, null,
                    [new("COCA LON 320", cocaId, false, null, 1, "Két", 192000, 0, 10, false, false, 12, true, "Két")]),
                CancellationToken.None);
            Assert.Null(err);
            Assert.Equal(1, res!.MappingsSaved);
        }
        await using (var check = NewDb(name))
        {
            var m = await check.PosAiInvoiceMappings.SingleAsync(x => x.ProductId == cocaId);
            Assert.Equal((12m, 2), (m.UnitFactor, m.UseCount));
        }
    }

    [Fact]
    public async Task Confirm_complete_adds_stock_in_base_units_and_supplier_debt()
    {
        var name = Guid.NewGuid().ToString();
        Guid supId, tigerId, cocaId;
        await using (var db = NewDb(name))
        {
            (supId, tigerId, cocaId) = await SeedAsync(db);
        }
        await using (var db = NewDb(name))
        {
            var (res, err) = await new PosAiInvoiceService(db, new FakeGemini("{}")).ConfirmAsync(
                Store, null, "owner@test.local", () => Guid.NewGuid(),
                Request(supId, tigerId, cocaId, complete: true, paid: 58200), CancellationToken.None);
            Assert.Null(err);
            Assert.Equal("Completed", res!.Status);
            Assert.Equal(1058200, res.GrandTotal);
        }
        await using var check = NewDb(name);
        Assert.Equal(48, (await check.PosProducts.SingleAsync(p => p.Id == tigerId)).OnHandQty); // 2 thùng × 24
        Assert.Equal(24, (await check.PosProducts.SingleAsync(p => p.Id == cocaId)).OnHandQty);
        Assert.Equal(1_000_000, (await check.PosSuppliers.SingleAsync(s => s.Id == supId)).CurrentDebt);
        Assert.True(await check.PosSupplierPayments.AnyAsync(p => p.SupplierId == supId && p.Amount == 58200));
    }

    [Fact]
    public async Task Confirm_rejects_line_without_product_and_creates_supplier_when_asked()
    {
        await using var db = NewDb();
        var (_, tigerId, _) = await SeedAsync(db);
        var svc = new PosAiInvoiceService(db, new FakeGemini("{}"));

        var (_, err) = await svc.ConfirmAsync(Store, null, "a", () => Guid.NewGuid(),
            new InvoiceConfirmRequest(null, false, null, null, null, null, null, null, 0, false, 0, null, null,
                [new("Hàng lạ", null, false, null, 1, null, 1000, 0, 0, false, false)]), CancellationToken.None);
        Assert.Contains("chưa chọn hàng", err);

        var (res, err2) = await svc.ConfirmAsync(Store, null, "a", () => Guid.NewGuid(),
            new InvoiceConfirmRequest(null, true, "Đại lý Minh Anh", "0912 345 678", null, null, null, null, 0, false, 0, null, null,
                [new("Bia Tiger lon 330ml", tigerId, false, null, 3, "Lon", 15000, 0, 10, false, false)]), CancellationToken.None);
        Assert.Null(err2);
        Assert.True(res!.SupplierCreated);
        var sup = await db.PosSuppliers.SingleAsync(s => s.Id == res.SupplierId);
        Assert.Equal(("Đại lý Minh Anh", "NCC0002"), (sup.Name, sup.SupplierCode));
    }
}
