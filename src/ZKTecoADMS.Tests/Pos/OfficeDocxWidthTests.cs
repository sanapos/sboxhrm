using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Xuất Word (.docx qua LibreOffice): bảng giữ đúng độ rộng như bản in.</summary>
public class OfficeDocxWidthTests
{
    [Fact]
    public void Kho_giay_tu_khoa_doi_sang_so_do_cho_Writer()
    {
        // Writer bỏ qua «size: A4 portrait» → file Word khổ Letter, khung ký tràn trang 2.
        Assert.Contains("@page { size: 21cm 29.7cm; margin: 12mm; }",
            OfficePdfConverter.NumericPageSize("<style>@page { size: A4 portrait; margin: 12mm; }</style>"));
        Assert.Contains("@page{size:21cm 14.8cm;margin:8mm}",
            OfficePdfConverter.NumericPageSize("<style>@page{size:A5 landscape;margin:8mm}</style>"));
        Assert.Contains("@page{size:21cm 29.7cm;margin:10mm 8mm}",
            OfficePdfConverter.NumericPageSize("<style>@page{size:A4;margin:10mm 8mm}</style>"));
        Assert.Equal("<p>size: A4</p>", OfficePdfConverter.NumericPageSize("<p>size: A4</p>")); // chỉ trong @page
    }

    [Fact]
    public void Do_rong_trong_style_thanh_thuoc_tinh_va_cot_thieu_nhan_phan_con_lai()
    {
        const string html = """
            <table style="width:100%;border-collapse:collapse"><thead><tr>
            <th style="width:5%">STT</th><th style="text-align:left">Tên hàng</th><th style="width:7%">ĐVT</th>
            <th style="width:7%">SL</th><th style="width:13%">Đơn giá</th><th style="width:14%">Thành tiền</th><th style="width:8%">BH</th>
            </tr></thead><tbody><tr><td>1</td><td>Tủ bếp</td><td>md</td><td>4,5</td><td>1</td><td>2</td><td></td></tr></tbody></table>
            <table style="width:52%;margin-left:auto"><tr><td>Tổng</td><td>1</td></tr></table>
            <thead><tr><td style="width:30%">x</td></tr></thead>
            """;
        var o = OfficePdfConverter.WidthAttributesForWriter(html);
        Assert.Contains("<table width=\"100%\"", o);
        Assert.Contains("<td width=\"48%\" style=\"border:none\">&nbsp;</td>", o);                                // bảng tổng 52% canh phải
        Assert.Contains("<p style=\"margin:0;font-size:2px", o);                       // ngăn 2 bảng liền nhau
        Assert.Contains("<th width=\"5%\"", o);
        Assert.Contains("<th width=\"46%\" style=\"text-align:left\">Tên hàng", o);   // 100 − (5+7+7+13+14+8)
        Assert.DoesNotContain("<thead width", o);                                     // không khớp nhầm <thead>
        var dump = Environment.GetEnvironmentVariable("SBOX_DOCX_DUMP");
        if (!string.IsNullOrEmpty(dump) && File.Exists(dump))
            File.WriteAllText(dump + ".w.html", OfficePdfConverter.WidthAttributesForWriter(File.ReadAllText(dump)), new System.Text.UTF8Encoding(true));
    }
}
