using System.Text.Json;
using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

/// <summary>AI sửa mẫu in V2: chỉ nhận khối hợp lệ, không cho đổi khổ giấy / loại chứng từ.</summary>
public class PrintTemplateAiTests
{
    static JsonElement Original() => JsonDocument.Parse("""
        {"version":1,"paperSize":"K80","printerProfile":"sunmi_k80","documentType":"SaleInvoice",
         "blocks":[{"type":"text","text":"CỬA HÀNG","style":{"fontSize":32,"bold":true,"align":"center"}}]}
        """).RootElement;

    [Fact]
    public void Giu_kho_giay_va_loai_chung_tu_cu()
    {
        var r = PosPrintTemplateAiService.Validate("""
            {"template":{"version":9,"paperSize":"K58","printerProfile":"x","documentType":"KitchenSlip",
              "blocks":[{"type":"text","text":"CỬA HÀNG","style":{"fontSize":40}}]},
             "summary":"Tăng cỡ chữ tiêu đề."}
            """, Original());
        Assert.Equal("K80", r.Template["paperSize"]!.GetValue<string>());
        Assert.Equal("SaleInvoice", r.Template["documentType"]!.GetValue<string>());
        Assert.Equal(1, r.Template["version"]!.GetValue<int>());
        Assert.Equal("Tăng cỡ chữ tiêu đề.", r.Summary);
    }

    [Fact]
    public void Bo_khoi_sai_loai_va_bao_canh_bao()
    {
        var r = PosPrintTemplateAiService.Validate("""
            {"template":{"blocks":[{"type":"text","text":"A"},{"type":"emoji"},{"text":"không type"}]}}
            """, Original());
        Assert.Single(r.Template["blocks"]!.AsArray());
        Assert.Single(r.Warnings);
        Assert.Equal("Đã sửa mẫu theo yêu cầu.", r.Summary);
    }

    [Fact]
    public void Nhan_mau_tra_thang_khong_boc_template()
    {
        var r = PosPrintTemplateAiService.Validate("""{"blocks":[{"type":"divider"}]}""", Original());
        Assert.Equal("divider", r.Template["blocks"]![0]!["type"]!.GetValue<string>());
        Assert.Equal("K80", r.Template["paperSize"]!.GetValue<string>());
    }

    [Fact]
    public void Mau_rong_thi_bao_loi()
    {
        Assert.Throws<InvalidOperationException>(() =>
            PosPrintTemplateAiService.Validate("""{"template":{"blocks":[]}}""", Original()));
        Assert.Throws<InvalidOperationException>(() =>
            PosPrintTemplateAiService.Validate("""{"summary":"không làm được"}""", Original()));
    }
}
