using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Số báo giá / hợp đồng theo thiết lập cửa hàng: mặc định như cũ, mẫu riêng, nhập tay + kiểm trùng.</summary>
[Collection("pos-pg")]
public class PosDocNumberingFlowTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    sealed class Env : IWebHostEnvironment
    {
        public string WebRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
        public string ApplicationName { get; set; } = "test";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public string EnvironmentName { get; set; } = "Test";
    }

    static PosQuotesController Quotes(ZKTecoDbContext db, Guid store) =>
        PosPgFixture.As(new PosQuotesController(db, new Env()), store);

    static PosQuotesController.QuoteSaveDto Dto(string? no = null) => new(
        null, "Anh Bình", "0900000000", null, null, null, null, null, null,
        [new PosQuotesController.QuoteLineInput(null, null, "Tủ bếp", "md", 2, 5_000_000)],
        QuoteNo: no);

    async Task<Guid> StoreAsync(string? extraJson)
    {
        var store = await Fx.NewStoreAsync();
        if (extraJson == null) return store;
        await using var db = Fx.NewDb();
        db.PosStoreSellSettings.Add(new PosStoreSellSettings
        {
            Id = Guid.NewGuid(), StoreId = store, ExtraJson = extraJson, IsActive = true,
        });
        await db.SaveChangesAsync();
        return store;
    }

    async Task<PosQuotesController.QuoteDto> CreateAsync(Guid store, string? no = null)
    {
        await using var db = Fx.NewDb();
        return Data(await Quotes(db, store).Create(Dto(no)));
    }

    async Task<List<string>> SlipNosAsync(Guid quoteId)
    {
        await using var db = Fx.NewDb();
        return await db.PosQuoteDocuments.Where(d => d.QuoteId == quoteId && d.Kind == PosQuoteDocumentKind.Quote)
            .Select(d => d.DocNo).ToListAsync();
    }

    [Fact]
    public async Task Mac_dinh_giu_kieu_so_cu_va_phieu_mang_so_bao_gia()
    {
        if (NoDb) return;
        var store = await StoreAsync(null);
        var today = VnTimeHelper.NowVn().ToString("ddMMyyyy");
        var a = await CreateAsync(store);
        var b = await CreateAsync(store, "TU-NHAP-01"); // chưa bật «Tự nhập» → bỏ qua số gửi lên
        Assert.Equal($"BG{today}0001", a.QuoteNo);
        Assert.Equal($"BG{today}0002", b.QuoteNo);
        Assert.Equal([a.QuoteNo], await SlipNosAsync(a.Id));
    }

    [Fact]
    public async Task Mau_rieng_tu_nhay()
    {
        if (NoDb) return;
        var store = await StoreAsync("""{"docNumbering":{"quote":{"pattern":"{SEQ:3}/{YYYY}/BG-SANA"}}}""");
        var year = VnTimeHelper.NowVn().Year;
        Assert.Equal($"001/{year}/BG-SANA", (await CreateAsync(store)).QuoteNo);
        Assert.Equal($"002/{year}/BG-SANA", (await CreateAsync(store)).QuoteNo);
        await using var db = Fx.NewDb();
        var next = Data(await Quotes(db, store).Numbering("Quote"));
        Assert.False(next.Manual);
        Assert.Equal($"003/{year}/BG-SANA", next.Next);
    }

    [Fact]
    public async Task Tu_nhap_so_bao_gia_kiem_trung_va_doi_so()
    {
        if (NoDb) return;
        var store = await StoreAsync("""{"docNumbering":{"quote":{"manual":true,"pattern":"BG-{SEQ:3}"}}}""");
        var a = await CreateAsync(store, " BG/2026/TH-01 ");
        Assert.Equal("BG/2026/TH-01", a.QuoteNo);
        Assert.Equal("BG-001", (await CreateAsync(store)).QuoteNo); // trống → tự nhảy theo mẫu

        await using (var db = Fx.NewDb())
            Assert.Contains("đã có", Error(await Quotes(db, store).Create(Dto("BG/2026/TH-01"))));

        await using (var db = Fx.NewDb())
        {
            var upd = Data(await Quotes(db, store).Update(a.Id, Dto("BG/2026/TH-01A")));
            Assert.Equal("BG/2026/TH-01A", upd.QuoteNo);
        }
        Assert.Equal(["BG/2026/TH-01A"], await SlipNosAsync(a.Id));
        await using (var db = Fx.NewDb())
            Assert.Contains("đã có", Error(await Quotes(db, store).Update(a.Id, Dto("BG-001"))));
    }

    [Fact]
    public async Task Tu_nhap_so_hop_dong()
    {
        if (NoDb) return;
        var store = await StoreAsync("""{"docNumbering":{"contract":{"manual":true,"pattern":"{SEQ:2}/{YYYY}/HĐKT"}}}""");
        var a = await CreateAsync(store);
        var b = await CreateAsync(store);
        var year = VnTimeHelper.NowVn().Year;

        await using (var db = Fx.NewDb())
        {
            var n = Data(await Quotes(db, store).Numbering("Contract"));
            Assert.True(n.Manual);
            Assert.Equal($"01/{year}/HĐKT", n.Next);
        }
        await using (var db = Fx.NewDb())
        {
            var doc = Data(await Quotes(db, store).CreateDocument(a.Id,
                new PosQuotesController.CreateQuoteDocumentDto("Contract", null, DocNo: "15/2026/HĐKT-SANA")));
            Assert.Equal("15/2026/HĐKT-SANA", doc.DocNo);
        }
        await using (var db = Fx.NewDb())
            Assert.Contains("đã có", Error(await Quotes(db, store).CreateDocument(b.Id,
                new PosQuotesController.CreateQuoteDocumentDto("Contract", null, DocNo: "15/2026/HĐKT-SANA"))));
        await using (var db = Fx.NewDb())
        {
            var doc = Data(await Quotes(db, store).CreateDocument(b.Id,
                new PosQuotesController.CreateQuoteDocumentDto("Contract", null)));
            Assert.Equal($"01/{year}/HĐKT", doc.DocNo);
        }
    }
}
