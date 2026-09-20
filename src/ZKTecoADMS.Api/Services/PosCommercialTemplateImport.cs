using System.IO.Compression;
using System.Net;
using System.Text;
using System.Xml.Linq;

namespace ZKTecoADMS.Api.Services;

/// <summary>Word (.docx) / PDF → HTML A4 để soạn mẫu báo giá / HĐ / biên bản.</summary>
public static class PosCommercialTemplateImport
{
    public static bool TryImport(string fileName, byte[] bytes, out string html, out string error)
    {
        html = "";
        error = "";
        var ext = Path.GetExtension(fileName ?? "").ToLowerInvariant();
        try
        {
            if (ext is ".docx" or ".doc")
            {
                html = WrapA4(DocxToHtml(bytes));
                return true;
            }
            if (ext == ".pdf")
            {
                html = WrapA4(PdfHintHtml(fileName, bytes.Length));
                return true;
            }
            error = "Chỉ nhận file Word (.docx) hoặc PDF.";
            return false;
        }
        catch (Exception ex)
        {
            error = "Không đọc được file: " + ex.Message;
            return false;
        }
    }

    static string WrapA4(string body) =>
        "<div style=\"font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:16px;min-height:277mm\">" +
        body +
        "<hr style=\"margin:20px 0;border:none;border-top:1px dashed #999\"/>" +
        "<div style=\"font-size:11px;color:#555\">" +
        "Chèn trường động (giống hóa đơn): {Ten_Cua_Hang} {Dia_Chi_Chi_Nhanh} {Khach_Hang} {SDT} {Dia_Chi_Khach_Hang} " +
        "{Ma_Bao_Gia} {Han_Bao_Gia} {Tong_Tien_Hang} {Chiet_Khau_Hoa_Don} {Tien_Thue} {Tong_Cong} {Tong_Cong_Bang_Chu} " +
        "{Hinh_Thuc_Thanh_Toan} {Dieu_Khoan}<br/>" +
        "Bảng hàng: <!--BEGIN_ITEMS--> … {STT} {Ma_Hang} {Ten_Hang_Hoa} {Don_Gia} {So_Luong} {Thanh_Tien} {Bao_Hanh} <!--END_ITEMS-->" +
        "</div></div>";

    static string DocxToHtml(byte[] bytes)
    {
        using var ms = new MemoryStream(bytes);
        using var zip = new ZipArchive(ms, ZipArchiveMode.Read);
        var entry = zip.GetEntry("word/document.xml")
            ?? throw new InvalidOperationException("File Word không hợp lệ (thiếu document.xml).");
        using var stream = entry.Open();
        var doc = XDocument.Load(stream);
        XNamespace w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
        var sb = new StringBuilder();
        foreach (var p in doc.Descendants(w + "p"))
        {
            var text = string.Concat(p.Descendants(w + "t").Select(t => t.Value));
            if (string.IsNullOrWhiteSpace(text))
            {
                sb.Append("<div style=\"height:10px\"></div>");
                continue;
            }
            sb.Append("<p style=\"margin:0 0 8px;line-height:1.45\">")
                .Append(WebUtility.HtmlEncode(text))
                .Append("</p>");
        }
        if (sb.Length == 0)
            throw new InvalidOperationException("File Word không có nội dung chữ.");
        return sb.ToString();
    }

    static string PdfHintHtml(string fileName, int bytes)
    {
        var safe = WebUtility.HtmlEncode(Path.GetFileName(fileName));
        return
            "<p><b>Mẫu PDF: " + safe + "</b> (" + (bytes / 1024) + " KB)</p>" +
            "<p>PDF giữ bố cục gốc khó sửa chữ. Hãy dán nội dung cần in bên dưới, rồi chèn token " +
            "<code>{Khach_Hang}</code>, <code>{Tong_Cong}</code>, bảng <!--BEGIN_ITEMS-->.</p>" +
            "<p>Gợi ý: xuất lại file Word từ PDF rồi tải lên để lấy đủ đoạn văn.</p>" +
            DefaultItemTable();
    }

    static string DefaultItemTable() =>
        "<table style=\"width:100%;border-collapse:collapse;margin-top:12px\">" +
        "<thead><tr style=\"background:#f3f4f6\">" +
        "<th style=\"border:1px solid #ccc;padding:6px\">STT</th>" +
        "<th style=\"border:1px solid #ccc;padding:6px\">Mã</th>" +
        "<th style=\"border:1px solid #ccc;padding:6px\">Hàng hóa / dịch vụ</th>" +
        "<th style=\"border:1px solid #ccc;padding:6px\">BH</th>" +
        "<th style=\"border:1px solid #ccc;padding:6px;text-align:right\">Đơn giá</th>" +
        "<th style=\"border:1px solid #ccc;padding:6px;text-align:center\">SL</th>" +
        "<th style=\"border:1px solid #ccc;padding:6px;text-align:right\">Thành tiền</th>" +
        "</tr></thead><tbody><!--BEGIN_ITEMS--><tr>" +
        "<td style=\"border:1px solid #ccc;padding:5px;text-align:center\">{STT}</td>" +
        "<td style=\"border:1px solid #ccc;padding:5px\">{Ma_Hang}</td>" +
        "<td style=\"border:1px solid #ccc;padding:5px\">{Ten_Hang_Hoa}</td>" +
        "<td style=\"border:1px solid #ccc;padding:5px\">{Bao_Hanh}</td>" +
        "<td style=\"border:1px solid #ccc;padding:5px;text-align:right\">{Don_Gia}</td>" +
        "<td style=\"border:1px solid #ccc;padding:5px;text-align:center\">{So_Luong}</td>" +
        "<td style=\"border:1px solid #ccc;padding:5px;text-align:right\">{Thanh_Tien}</td>" +
        "</tr><!--END_ITEMS--></tbody></table>" +
        "<div style=\"text-align:right;margin-top:12px\">" +
        "<div>Tổng tiền hàng: <b>{Tong_Tien_Hang}</b></div>" +
        "<div>Chiết khấu: <b>{Chiet_Khau_Hoa_Don}</b></div>" +
        "<div>Thuế: <b>{Tien_Thue}</b></div>" +
        "<div>Tổng cộng: <b>{Tong_Cong}</b></div>" +
        "<div><i>{Tong_Cong_Bang_Chu}</i></div></div>";
}
