using System.Globalization;
using System.Text;
using ClosedXML.Excel;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

public static class PosQuoteExportService
{
    public static byte[] BuildExcel(PosQuote quote, PosStoreCommercialProfile? profile)
    {
        var vn = CultureInfo.GetCultureInfo("vi-VN");
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("BaoGia");
        ws.Column(1).Width = 6;
        ws.Column(2).Width = 14;
        ws.Column(3).Width = 36;
        ws.Column(4).Width = 10;
        ws.Column(5).Width = 8;
        ws.Column(6).Width = 14;
        ws.Column(7).Width = 14;
        ws.Column(8).Width = 12;

        var shop = profile?.CompanyName ?? quote.Store?.Name ?? "";
        var r = 1;
        ws.Cell(r, 1).Value = "BẢNG BÁO GIÁ";
        ws.Range(r, 1, r, 8).Merge().Style.Font.SetBold().Font.SetFontSize(16);
        r += 2;
        ws.Cell(r++, 1).Value = "Số BG:"; ws.Cell(r - 1, 2).Value = quote.QuoteNo;
        ws.Cell(r++, 1).Value = "Công ty:"; ws.Cell(r - 1, 2).Value = shop;
        ws.Cell(r++, 1).Value = "MST:"; ws.Cell(r - 1, 2).Value = profile?.TaxCode ?? "";
        ws.Cell(r++, 1).Value = "Khách:"; ws.Cell(r - 1, 2).Value = quote.CustomerName ?? "";
        ws.Cell(r++, 1).Value = "SĐT:"; ws.Cell(r - 1, 2).Value = quote.CustomerPhone ?? "";
        ws.Cell(r++, 1).Value = "Hạn BG:"; ws.Cell(r - 1, 2).Value =
            quote.ValidUntil?.ToLocalTime().ToString("dd/MM/yyyy", vn) ?? "";
        r++;

        var hdr = r;
        ws.Cell(r, 1).Value = "STT";
        ws.Cell(r, 2).Value = "Mã";
        ws.Cell(r, 3).Value = "Tên hàng";
        ws.Cell(r, 4).Value = "ĐVT";
        ws.Cell(r, 5).Value = "SL";
        ws.Cell(r, 6).Value = "Đơn giá";
        ws.Cell(r, 7).Value = "Thành tiền";
        ws.Cell(r, 8).Value = "BH";
        ws.Range(r, 1, r, 8).Style.Font.SetBold().Fill.SetBackgroundColor(XLColor.LightGray);
        r++;

        var i = 1;
        foreach (var line in quote.Lines.Where(l => l.Deleted == null).OrderBy(l => l.SortOrder))
        {
            ws.Cell(r, 1).Value = i++;
            ws.Cell(r, 2).Value = line.ProductCode ?? "";
            ws.Cell(r, 3).Value = line.ProductName;
            ws.Cell(r, 4).Value = line.UnitName ?? "";
            ws.Cell(r, 5).Value = (double)line.Qty;
            ws.Cell(r, 6).Value = (double)line.UnitPrice;
            ws.Cell(r, 7).Value = (double)line.LineTotal;
            ws.Cell(r, 8).Value = line.WarrantyMonths is > 0 ? $"{line.WarrantyMonths} tháng" : "";
            r++;
        }

        r++;
        ws.Cell(r, 6).Value = "Tổng tiền hàng"; ws.Cell(r, 7).Value = (double)quote.SubTotal; r++;
        ws.Cell(r, 6).Value = "Chiết khấu"; ws.Cell(r, 7).Value = (double)quote.Discount; r++;
        ws.Cell(r, 6).Value = "Thuế"; ws.Cell(r, 7).Value = (double)quote.VatAmount; r++;
        ws.Cell(r, 6).Value = "Tổng cộng"; ws.Cell(r, 7).Value = (double)quote.Total;
        ws.Cell(r, 6).Style.Font.SetBold();
        ws.Cell(r, 7).Style.Font.SetBold();
        r += 2;

        var preVat = Math.Max(0,
            quote.Lines.Where(l => l.Deleted == null)
                .Sum(l => Math.Max(0, l.Qty * l.UnitPrice - l.DiscountAmount)) - quote.Discount);
        ws.Cell(r++, 1).Value = "Tiền cọc:"; ws.Cell(r - 1, 2).Value = (double)quote.DepositAmount;
        ws.Cell(r++, 1).Value = "% cọc / trước VAT:";
        ws.Cell(r - 1, 2).Value = quote.DepositPercent is > 0
            ? $"{quote.DepositPercent:0.##}% / {preVat:#,##0}"
            : "";
        ws.Cell(r++, 1).Value = "TK nhận cọc:";
        ws.Cell(r - 1, 2).Value =
            $"{profile?.BankAccountNumber} — {profile?.BankName} — {profile?.BankAccountHolder}";

        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return ms.ToArray();
    }

    public static byte[] BuildWordHtml(string renderedHtml, string title)
    {
        var safe = System.Net.WebUtility.HtmlEncode(title);
        var doc = "<html xmlns:o=\"urn:schemas-microsoft-com:office:office\" " +
                  "xmlns:w=\"urn:schemas-microsoft-com:office:word\">" +
                  "<head><meta charset=\"utf-8\"><title>" + safe + "</title></head><body>" +
                  renderedHtml + "</body></html>";
        return Encoding.UTF8.GetBytes(doc);
    }
}
