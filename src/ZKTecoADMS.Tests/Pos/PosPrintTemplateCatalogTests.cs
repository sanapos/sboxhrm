using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Mẫu chung báo giá: DB còn mẫu chung «K80 ★» / «K58» từ trước khi báo giá có A4 (sửa mẫu chung không lưu được vì
/// DbContext mặc định NoTracking) → cửa hàng mới nhận nhầm mẫu tên «K80 ★». Nay mẫu chung thừa bị tắt, cửa hàng mới
/// nhận A4, bản cửa hàng nhận nhầm được sửa mà không đè lời văn cửa hàng đã tự sửa.
/// </summary>
public class PosPrintTemplateCatalogTests
{
    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    const string V2Thermal = "<!--POS_TEMPLATE_V2-->\n{\"version\":1,\"paperSize\":\"K80\",\"blocks\":[]}";
    const string OldA4Html = "<!--POS_A4_V6 paper=\"A4\"--><div>BẢNG BÁO GIÁ cũ {Ten_Hang_Hoa}</div>";

    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;
    readonly Guid _oldK80Cat = Guid.NewGuid();
    readonly Guid _oldA4Cat = Guid.NewGuid();

    public PosPrintTemplateCatalogTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();

        // Mẫu chung báo giá như trên máy chủ thật: bộ cũ (K80 ★ / K58 / A5) + A4 ★ thêm sau, tất cả đang bật.
        Catalog(_oldK80Cat, "K80 ★", PosPrintPaperSize.K80, 0, true, V2Thermal);
        Catalog(Guid.NewGuid(), "K58", PosPrintPaperSize.K58, 1, false, V2Thermal);
        Catalog(Guid.NewGuid(), "A5", PosPrintPaperSize.A5, 2, false, "<div>A5 cũ</div>");
        Catalog(_oldA4Cat, "A4 ★", PosPrintPaperSize.A4, 0, true, OldA4Html);
        _db.SaveChanges();
    }

    void Catalog(Guid id, string name, PosPrintPaperSize paper, int sort, bool rec, string html) =>
        _db.PosPrintTemplateCatalogs.Add(new PosPrintTemplateCatalog
        {
            Id = id, Name = name, DocumentType = PosPrintDocumentType.Quote, PaperSize = paper, SortOrder = sort,
            IsRecommended = rec, IsActive = true, HtmlContent = html, CreatedAt = DateTime.UtcNow, CreatedBy = "system",
        });

    Guid StoreTemplate(Guid store, string name, PosPrintPaperSize paper, string html, Guid? catalogId)
    {
        var id = Guid.NewGuid();
        _db.PosPrintTemplates.Add(new PosPrintTemplate
        {
            Id = id, StoreId = store, Name = name, DocumentType = PosPrintDocumentType.Quote, PaperSize = paper,
            HtmlContent = html, IsDefault = true, IsActive = true, SourceCatalogId = catalogId,
            CreatedAt = DateTime.UtcNow, CreatedBy = "system",
        });
        _db.SaveChanges();
        return id;
    }

    PosPrintTemplatesController Ctl(Guid store) => new(_db)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", Guid.NewGuid().ToString()),
                    new Claim(ClaimTypes.Role, "Admin"),
                    new Claim(ClaimTypes.Email, "chu@test"),
                    new Claim(ClaimTypeNames.StoreId, store.ToString()),
                ], "test")),
            },
        },
    };

    static JsonElement Data(ActionResult<ZKTecoADMS.Application.Models.AppResponse<object>> r)
    {
        var obj = r.Result is ObjectResult o ? o.Value : r.Value;
        return JsonDocument.Parse(JsonSerializer.Serialize(obj, Json)).RootElement.GetProperty("data");
    }

    PosPrintTemplate Row(Guid id) => _db.PosPrintTemplates.AsNoTracking().Single(t => t.Id == id);

    [Fact]
    public async Task Catalog_bao_gia_chi_con_A4_va_A5()
    {
        var items = Data(await Ctl(Guid.NewGuid()).ListCatalog(PosPrintDocumentType.Quote)).EnumerateArray().ToList();

        Assert.Equal(["A4", "A5"], items.Select(i => i.GetProperty("paperSize").GetString()!).Order().ToArray());
        Assert.DoesNotContain(items, i => i.GetProperty("name").GetString()!.Contains("K80"));
        // Mẫu chung A4 theo mẫu chuẩn mới nhất (sửa mẫu chuẩn tới được mẫu chung).
        var a4 = items.Single(i => i.GetProperty("paperSize").GetString() == "A4");
        Assert.Contains("POS_A4_V9", a4.GetProperty("htmlContent").GetString());
        Assert.True(a4.GetProperty("isRecommended").GetBoolean());
    }

    [Fact]
    public async Task Cua_hang_moi_nhan_mau_bao_gia_A4_khong_phai_K80()
    {
        var store = Guid.NewGuid();
        var items = Data(await Ctl(store).List(PosPrintDocumentType.Quote, null)).EnumerateArray().ToList();

        var t = Assert.Single(items);
        Assert.Equal("A4", t.GetProperty("paperSize").GetString());
        Assert.Equal("Báo giá A4 ★", t.GetProperty("name").GetString());
        Assert.True(t.GetProperty("isDefault").GetBoolean());
        Assert.Contains("BẢNG BÁO GIÁ", t.GetProperty("htmlContent").GetString());
        Assert.Contains("POS_A4_V9", t.GetProperty("htmlContent").GetString());
    }

    [Fact]
    public async Task Cua_hang_da_nhan_nham_K80_duoc_sua_giu_loi_van_da_sua()
    {
        // Cửa hàng A: mẫu K80 nguyên trạng (JSON nhiệt — không in được A4) → thay mẫu A4 chuẩn.
        var storeA = Guid.NewGuid();
        var thermal = StoreTemplate(storeA, "K80 ★", PosPrintPaperSize.K80, V2Thermal, _oldK80Cat);
        // Cửa hàng B: app đã đổi sang A4 và chủ cửa hàng đã sửa câu chữ, chỉ còn tên «K80 ★» → chỉ đổi tên.
        var storeB = Guid.NewGuid();
        const string edited = "<!--POS_A4_V9 paper=\"A4\" rev=\"2\"--><div>Báo giá riêng của tiệm {Ten_Hang_Hoa}</div>";
        var renamed = StoreTemplate(storeB, "K80 ★", PosPrintPaperSize.A4, edited, _oldK80Cat);

        await Ctl(storeA).List(PosPrintDocumentType.Quote, null);

        var a = Row(thermal);
        Assert.Equal(PosPrintPaperSize.A4, a.PaperSize);
        Assert.Equal("Báo giá A4 ★", a.Name);
        Assert.Contains("POS_A4_V9", a.HtmlContent);
        Assert.Equal(_oldA4Cat, a.SourceCatalogId);

        var b = Row(renamed);
        Assert.Equal("Báo giá A4 ★", b.Name);
        Assert.Equal(edited, b.HtmlContent);
    }

    [Fact]
    public async Task Cap_nhat_mau_chung_khong_de_mau_cua_hang_da_sua()
    {
        var untouched = StoreTemplate(Guid.NewGuid(), "A4 ★", PosPrintPaperSize.A4, OldA4Html, _oldA4Cat);
        const string custom = "<!--POS_A4_V6 paper=\"A4\"--><div>Tiệm tự viết lại {Ten_Hang_Hoa}</div>";
        var edited = StoreTemplate(Guid.NewGuid(), "Mẫu của tiệm", PosPrintPaperSize.A4, custom, _oldA4Cat);

        await Ctl(Guid.NewGuid()).ListCatalog(PosPrintDocumentType.Quote);

        Assert.Contains("POS_A4_V9", Row(untouched).HtmlContent);
        var e = Row(edited);
        Assert.Equal(custom, e.HtmlContent);
        Assert.Equal("Mẫu của tiệm", e.Name);
    }
}
