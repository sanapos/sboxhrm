using System.Text.RegularExpressions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests;

/// <summary>Mẫu hóa đơn khổ trang A4 / A5 (máy in văn phòng).</summary>
public class PrintSheetTemplateTests
{
    [Fact]
    public void Hoa_don_co_du_kho_K80_K58_A5_A4()
    {
        var sizes = PosPrintTemplateDefaults.SizesForDocument(PosPrintDocumentType.SaleInvoice);
        Assert.Equal(
            new[] { PosPrintPaperSize.K80, PosPrintPaperSize.K58, PosPrintPaperSize.A5, PosPrintPaperSize.A4 },
            sizes);
    }

    [Theory]
    [InlineData(PosPrintPaperSize.A4)]
    [InlineData(PosPrintPaperSize.A5)]
    public void Mau_trang_khoi_dieu_kien_can_bang_va_du_truong(PosPrintPaperSize size)
    {
        var html = PosPrintTemplateDefaults.BuildHtml(PosPrintDocumentType.SaleInvoice, size);
        foreach (Match m in Regex.Matches(html, "<!--IF:([A-Za-z_]+)-->"))
            Assert.Contains("<!--ENDIF:" + m.Groups[1].Value + "-->", html);
        Assert.Equal(
            Regex.Matches(html, "<!--IF:").Count,
            Regex.Matches(html, "<!--ENDIF:").Count);
        Assert.Single(Regex.Matches(html, "<!--BEGIN_ITEMS-->"));
        foreach (var f in new[] { "{Ten_Cua_Hang}", "{Ma_Don_Hang}", "{Ten_Hang_Hoa}", "{So_Luong}",
                     "{Don_Gia}", "{Thanh_Tien}", "{Tong_Cong}", "{Phu_Thu}", "{Phi_Giao_Hang}", "{VAT}",
                     "{Tong_Cong_Bang_Chu}" })
            Assert.Contains(f, html);
    }

    [Fact]
    public void A5_gon_hon_A4_bo_cot_ma_hang_va_CK()
    {
        var a4 = PosPrintTemplateDefaults.BuildHtml(PosPrintDocumentType.SaleInvoice, PosPrintPaperSize.A4);
        var a5 = PosPrintTemplateDefaults.BuildHtml(PosPrintDocumentType.SaleInvoice, PosPrintPaperSize.A5);
        Assert.Contains("{Ma_Hang}", a4);
        Assert.Contains("{Chiet_Khau}", a4);
        Assert.DoesNotContain("{Ma_Hang}", a5);
        Assert.DoesNotContain("{Chiet_Khau}", a5);
    }
}
