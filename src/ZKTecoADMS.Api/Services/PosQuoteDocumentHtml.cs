using System.Globalization;
using System.Net;
using System.Text;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

public static class PosQuoteDocumentHtml
{
    public static string TitleOf(PosQuoteDocumentKind kind) => kind switch
    {
        PosQuoteDocumentKind.Quote => "BÁO GIÁ",
        PosQuoteDocumentKind.Contract => "HỢP ĐỒNG CUNG CẤP / THI CÔNG",
        PosQuoteDocumentKind.Handover => "BIÊN BẢN BÀN GIAO",
        PosQuoteDocumentKind.Acceptance => "BIÊN BẢN NGHIỆM THU",
        PosQuoteDocumentKind.StockIssue => "PHIẾU XUẤT KHO",
        _ => "CHỨNG TỪ",
    };

    public static string PrefixOf(PosQuoteDocumentKind kind) => kind switch
    {
        PosQuoteDocumentKind.Quote => "BG",
        PosQuoteDocumentKind.Contract => "HD",
        PosQuoteDocumentKind.Handover => "BB",
        PosQuoteDocumentKind.Acceptance => "NT",
        PosQuoteDocumentKind.StockIssue => "PX",
        _ => "CT",
    };

    public static string Build(PosQuote quote, PosQuoteDocumentKind kind, string docNo, string? extraNote)
    {
        var vn = CultureInfo.GetCultureInfo("vi-VN");
        var lines = quote.Lines.Where(l => l.Deleted == null).OrderBy(l => l.SortOrder).ToList();
        var sb = new StringBuilder();
        sb.Append("""
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <style>
            body{font-family:Arial,sans-serif;font-size:13px;color:#222;margin:24px}
            h1{font-size:20px;margin:0 0 4px;text-align:center}
            .sub{text-align:center;color:#555;margin-bottom:16px}
            table{width:100%;border-collapse:collapse;margin:12px 0}
            th,td{border:1px solid #ccc;padding:6px 8px}
            th{background:#f3f3f3;text-align:left}
            .r{text-align:right}
            .meta{margin:8px 0}
            .sign{display:flex;justify-content:space-between;margin-top:36px}
            .sign div{width:45%;text-align:center}
            .note{margin-top:12px;white-space:pre-wrap}
            </style></head><body>
            """);
        sb.Append("<h1>").Append(WebUtility.HtmlEncode(TitleOf(kind))).Append("</h1>");
        sb.Append("<div class=\"sub\">Số ").Append(WebUtility.HtmlEncode(docNo));
        sb.Append(" · Theo báo giá ").Append(WebUtility.HtmlEncode(quote.QuoteNo)).Append("</div>");
        sb.Append("<div class=\"meta\"><b>Khách hàng:</b> ")
            .Append(WebUtility.HtmlEncode(quote.CustomerName ?? "—"));
        if (!string.IsNullOrWhiteSpace(quote.CustomerPhone))
            sb.Append(" · ").Append(WebUtility.HtmlEncode(quote.CustomerPhone));
        sb.Append("<br/><b>Địa chỉ:</b> ")
            .Append(WebUtility.HtmlEncode(quote.CustomerAddress ?? "—"));
        if (quote.ValidUntil.HasValue && kind == PosQuoteDocumentKind.Quote)
            sb.Append("<br/><b>Hạn báo giá:</b> ")
                .Append(quote.ValidUntil.Value.ToString("dd/MM/yyyy", vn));
        sb.Append("</div>");

        sb.Append(kind switch
        {
            PosQuoteDocumentKind.Contract =>
                "<p>Hai bên thống nhất các hạng mục, đơn giá và điều khoản theo bảng dưới. Báo giá là phụ lục không tách rời của hợp đồng này.</p>",
            PosQuoteDocumentKind.Handover =>
                "<p>Bên A bàn giao cho bên B các hạng mục sau. Bên B đã kiểm tra số lượng / tình trạng tại thời điểm giao.</p>",
            PosQuoteDocumentKind.Acceptance =>
                "<p>Hai bên nghiệm thu các hạng mục. Đánh dấu đạt / tồn tại phần ghi chú dòng.</p>",
            PosQuoteDocumentKind.StockIssue =>
                "<p>Phiếu xuất kho theo báo giá (chứng từ thương mại — không phải hóa đơn bán hàng).</p>",
            _ => "",
        });

        sb.Append("<table><tr><th>STT</th><th>Hạng mục</th><th>ĐVT</th><th class=\"r\">SL</th>");
        if (kind is PosQuoteDocumentKind.Quote or PosQuoteDocumentKind.Contract)
            sb.Append("<th class=\"r\">Đơn giá</th><th class=\"r\">Thành tiền</th>");
        sb.Append("</tr>");
        var i = 1;
        foreach (var l in lines)
        {
            sb.Append("<tr><td>").Append(i++).Append("</td><td>")
                .Append(WebUtility.HtmlEncode(l.ProductName));
            if (!string.IsNullOrWhiteSpace(l.LineNote))
                sb.Append("<div style=\"color:#666;font-size:12px\">")
                    .Append(WebUtility.HtmlEncode(l.LineNote)).Append("</div>");
            sb.Append("</td><td>").Append(WebUtility.HtmlEncode(l.UnitName ?? "—"))
                .Append("</td><td class=\"r\">").Append(l.Qty.ToString("0.##", vn)).Append("</td>");
            if (kind is PosQuoteDocumentKind.Quote or PosQuoteDocumentKind.Contract)
            {
                sb.Append("<td class=\"r\">").Append(l.UnitPrice.ToString("#,##0", vn))
                    .Append("</td><td class=\"r\">").Append(l.LineTotal.ToString("#,##0", vn))
                    .Append("</td>");
            }
            sb.Append("</tr>");
        }
        sb.Append("</table>");

        if (kind is PosQuoteDocumentKind.Quote or PosQuoteDocumentKind.Contract)
        {
            sb.Append("<p class=\"r\"><b>Tổng cộng: ")
                .Append(quote.Total.ToString("#,##0", vn)).Append(" đ</b></p>");
        }

        if (!string.IsNullOrWhiteSpace(quote.Terms) &&
            kind is PosQuoteDocumentKind.Quote or PosQuoteDocumentKind.Contract)
        {
            sb.Append("<div class=\"note\"><b>Điều khoản:</b><br/>")
                .Append(WebUtility.HtmlEncode(quote.Terms)).Append("</div>");
        }
        if (!string.IsNullOrWhiteSpace(extraNote))
        {
            sb.Append("<div class=\"note\"><b>Ghi chú chứng từ:</b><br/>")
                .Append(WebUtility.HtmlEncode(extraNote)).Append("</div>");
        }

        sb.Append("""
            <div class="sign">
            <div>ĐẠI DIỆN BÊN A<br/><span style="color:#888">Ký, ghi rõ họ tên</span></div>
            <div>ĐẠI DIỆN BÊN B<br/><span style="color:#888">Ký, ghi rõ họ tên</span></div>
            </div></body></html>
            """);
        return sb.ToString();
    }
}
