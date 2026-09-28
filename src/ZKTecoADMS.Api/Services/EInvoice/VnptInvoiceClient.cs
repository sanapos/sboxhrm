using System.Net.Http.Headers;
using System.Text;
using System.Xml.Linq;

namespace ZKTecoADMS.Api.Services.EInvoice;

public record VnptResult(bool Ok, string? InvoiceNo, string? Pattern, string? Serial, string? ErrorCode, string? Error);

public record VnptListItem(
    string? Fkey,
    string? InvoiceNo,
    string? Pattern,
    string? Serial,
    DateTime? PublishDate,
    decimal Amount,
    string? CustomerName,
    int Status);

/// <summary>
/// VNPT Invoice (TT78) — SOAP web service trên domain riêng của doanh nghiệp,
/// vd. https://0101234567-tt78admin.vnpt-invoice.com.vn:
/// PublishService.ImportAndPublishInv, BusinessService.cancelInv / ReplaceInvoiceAction / deliverInvFkey,
/// PortalService.downloadInvPDFFkeyNoPay / getInvViewFkeyNoPay / listInvByCusFkey.
/// Account/ACpass = tài khoản web service; username/pass = tài khoản phát hành (admin).
/// </summary>
public class VnptInvoiceClient(IHttpClientFactory httpFactory, ILogger<VnptInvoiceClient> logger)
{
    static readonly XNamespace Tempuri = "http://tempuri.org/";
    static readonly XNamespace Soap = "http://schemas.xmlsoap.org/soap/envelope/";

    public static string NormalizeBaseUrl(string? raw)
    {
        var url = (raw ?? "").Trim().TrimEnd('/');
        foreach (var svc in new[] { "/PublishService.asmx", "/BusinessService.asmx", "/PortalService.asmx" })
        {
            var i = url.IndexOf(svc, StringComparison.OrdinalIgnoreCase);
            if (i >= 0) url = url[..i];
        }
        if (url.Length > 0 && !url.StartsWith("http", StringComparison.OrdinalIgnoreCase))
            url = "https://" + url;
        return url;
    }

    /// <summary>Trang tra cứu cho người mua: «…-tt78admin…» → «…-tt78…».</summary>
    public static string PortalLookupUrl(string baseUrl)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var lookup = root.Replace("admindemo.", "demo.", StringComparison.OrdinalIgnoreCase)
            .Replace("admin.", ".", StringComparison.OrdinalIgnoreCase);
        return lookup + "/Portal/Index/";
    }

    public async Task<VnptResult> ImportAndPublishAsync(
        string baseUrl, string account, string acPass, string username, string password,
        string xmlInvData, string pattern, string serial, CancellationToken ct = default)
    {
        var raw = await CallAsync(baseUrl, "PublishService", "ImportAndPublishInv", new()
        {
            ["Account"] = account,
            ["ACpass"] = acPass,
            ["xmlInvData"] = xmlInvData,
            ["username"] = username,
            ["pass"] = password,
            ["pattern"] = pattern,
            ["serial"] = serial,
            ["convert"] = "0",
        }, ct);
        return ParsePublishResult(raw, pattern, serial);
    }

    public async Task<VnptResult> ReplaceAsync(
        string baseUrl, string account, string acPass, string username, string password,
        string xmlInvData, string originalFkey, string pattern, string serial, CancellationToken ct = default)
    {
        var raw = await CallAsync(baseUrl, "BusinessService", "ReplaceInvoiceAction", new()
        {
            ["Account"] = account,
            ["ACpass"] = acPass,
            ["xmlInvData"] = xmlInvData,
            ["username"] = username,
            ["pass"] = password,
            ["fkey"] = originalFkey,
            ["Attachfile"] = "",
            ["convert"] = "0",
            ["pattern"] = pattern,
            ["serial"] = serial,
        }, ct);
        return ParsePublishResult(raw, pattern, serial);
    }

    public async Task<VnptResult> CancelAsync(
        string baseUrl, string account, string acPass, string username, string password,
        string fkey, CancellationToken ct = default)
    {
        var raw = await CallAsync(baseUrl, "BusinessService", "cancelInv", new()
        {
            ["Account"] = account,
            ["ACpass"] = acPass,
            ["fkey"] = fkey,
            ["userName"] = username,
            ["userPass"] = password,
        }, ct);
        return ParseOk(raw);
    }

    /// <summary>Gửi lại thông báo phát hành (email) theo fkey — VNPT gửi tới email trên hóa đơn.</summary>
    public async Task<VnptResult> DeliverAsync(
        string baseUrl, string username, string password, string fkey, CancellationToken ct = default)
    {
        var raw = await CallAsync(baseUrl, "BusinessService", "deliverInvFkey", new()
        {
            ["lstFkey"] = fkey,
            ["userName"] = username,
            ["userPass"] = password,
        }, ct);
        return ParseOk(raw);
    }

    public async Task<(bool Ok, byte[]? Pdf, string? Error)> DownloadPdfAsync(
        string baseUrl, string username, string password, string fkey, CancellationToken ct = default)
    {
        var raw = await CallAsync(baseUrl, "PortalService", "downloadInvPDFFkeyNoPay", new()
        {
            ["fkey"] = fkey,
            ["userName"] = username,
            ["userPass"] = password,
        }, ct);
        if (raw.Error != null) return (false, null, raw.Error);
        var v = (raw.Value ?? "").Trim();
        if (v.StartsWith("ERR", StringComparison.OrdinalIgnoreCase) || v.Length < 50)
            return (false, null, ErrText(v) ?? $"VNPT không trả file PDF ({v})");
        try
        {
            return (true, Convert.FromBase64String(v), null);
        }
        catch
        {
            return (false, null, "VNPT trả dữ liệu PDF không hợp lệ");
        }
    }

    public async Task<(bool Ok, string? Html, string? Error)> ViewHtmlAsync(
        string baseUrl, string username, string password, string fkey, CancellationToken ct = default)
    {
        var raw = await CallAsync(baseUrl, "PortalService", "getInvViewFkeyNoPay", new()
        {
            ["fkey"] = fkey,
            ["userName"] = username,
            ["userPass"] = password,
        }, ct);
        if (raw.Error != null) return (false, null, raw.Error);
        var v = (raw.Value ?? "").Trim();
        if (v.StartsWith("ERR", StringComparison.OrdinalIgnoreCase) || v.Length < 20)
            return (false, null, ErrText(v) ?? $"VNPT không trả hóa đơn ({v})");
        return (true, v, null);
    }

    /// <summary>Tra cứu hóa đơn theo fkey trong khoảng ngày (dd/MM/yyyy) — dùng cho đồng bộ.</summary>
    public async Task<(bool Ok, List<VnptListItem> Items, string? Error)> ListByFkeyAsync(
        string baseUrl, string username, string password, string fkey, DateTime fromLocal, DateTime toLocal,
        CancellationToken ct = default)
    {
        var raw = await CallAsync(baseUrl, "PortalService", "listInvByCusFkey", new()
        {
            ["key"] = fkey,
            ["fromDate"] = fromLocal.ToString("dd/MM/yyyy"),
            ["toDate"] = toLocal.ToString("dd/MM/yyyy"),
            ["userName"] = username,
            ["userPass"] = password,
        }, ct);
        if (raw.Error != null) return (false, [], raw.Error);
        var v = (raw.Value ?? "").Trim();
        if (v.StartsWith("ERR", StringComparison.OrdinalIgnoreCase))
            return (false, [], ErrText(v) ?? v);
        return (true, ParseList(v), null);
    }

    /// <summary>Kiểm tra tài khoản: gọi getInvViewFkeyNoPay với fkey giả — ERR:1 = sai tài khoản.</summary>
    public async Task<(bool Ok, string Message)> TestConnectionAsync(
        string baseUrl, string username, string password, CancellationToken ct = default)
    {
        var raw = await CallAsync(baseUrl, "PortalService", "getInvViewFkeyNoPay", new()
        {
            ["fkey"] = "sbox-ping-" + Guid.NewGuid().ToString("N")[..8],
            ["userName"] = username,
            ["userPass"] = password,
        }, ct);
        if (raw.Error != null) return (false, raw.Error);
        var v = (raw.Value ?? "").Trim();
        // ERR:1 = sai tài khoản; ERR:6/ERR:2 (không thấy hóa đơn giả) = đăng nhập được.
        if (v.Equals("ERR:1", StringComparison.OrdinalIgnoreCase))
            return (false, "Sai tài khoản / mật khẩu VNPT (ERR:1)");
        return (true,
            "Kết nối VNPT Invoice thành công (máy chủ phản hồi, tài khoản hợp lệ). " +
            "Kiểm tra kết nối không tạo hóa đơn — Account/ACpass web service chỉ xác minh khi phát hành.");
    }

    sealed record RawResult(string? Value, string? Error);

    async Task<RawResult> CallAsync(
        string baseUrl, string service, string operation, Dictionary<string, string> args, CancellationToken ct)
    {
        var root = NormalizeBaseUrl(baseUrl);
        if (string.IsNullOrWhiteSpace(root))
            return new(null, "Chưa nhập địa chỉ web service VNPT (vd. https://<MST>-tt78admin.vnpt-invoice.com.vn)");

        var body = new XElement(Tempuri + operation,
            args.Select(kv => new XElement(Tempuri + kv.Key, kv.Value ?? "")));
        var envelope = new XDocument(
            new XDeclaration("1.0", "utf-8", null),
            new XElement(Soap + "Envelope",
                new XAttribute(XNamespace.Xmlns + "soap", Soap),
                new XElement(Soap + "Body", body)));

        var client = httpFactory.CreateClient("vnpt-invoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}/{service}.asmx");
        req.Headers.TryAddWithoutValidation("SOAPAction", $"\"http://tempuri.org/{operation}\"");
        req.Content = new StringContent(
            envelope.Declaration + envelope.ToString(SaveOptions.DisableFormatting),
            Encoding.UTF8, "text/xml");
        req.Content.Headers.ContentType = new MediaTypeHeaderValue("text/xml") { CharSet = "utf-8" };
        try
        {
            using var res = await client.SendAsync(req, ct);
            var text = await res.Content.ReadAsStringAsync(ct);
            XDocument doc;
            try
            {
                doc = XDocument.Parse(text);
            }
            catch
            {
                return new(null, $"VNPT HTTP {(int)res.StatusCode}: {Trim(text)}");
            }
            var fault = doc.Descendants().FirstOrDefault(e => e.Name.LocalName == "faultstring");
            if (fault != null)
                return new(null, $"VNPT lỗi SOAP: {Trim(fault.Value)}");
            var result = doc.Descendants().FirstOrDefault(e => e.Name.LocalName == operation + "Result");
            if (result == null)
                return new(null, $"VNPT không trả kết quả {operation} (HTTP {(int)res.StatusCode})");
            return new(result.Value, null);
        }
        catch (TaskCanceledException)
        {
            return new(null, "Hết thời gian chờ VNPT Invoice. Thử đồng bộ lại.");
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "VNPT {Service}.{Op} failed", service, operation);
            return new(null, ex.Message);
        }
    }

    /// <summary>«OK:1/001;C24TAA-fkey_123» → số 123. «ERR:x» → lỗi.</summary>
    static VnptResult ParsePublishResult(RawResult raw, string pattern, string serial) =>
        raw.Error != null
            ? new(false, null, null, null, "EXCEPTION", raw.Error)
            : ParsePublishText(raw.Value, pattern, serial);

    public static VnptResult ParsePublishText(string? value, string pattern, string serial)
    {
        var v = (value ?? "").Trim();
        if (!v.StartsWith("OK", StringComparison.OrdinalIgnoreCase))
        {
            var code = v.Length > 0 ? v : "EMPTY";
            return new(false, null, null, null, code, ErrText(v) ?? $"VNPT từ chối: {Trim(v)}");
        }
        var rest = v.Length > 3 ? v[3..] : "";
        string? pat = pattern, ser = serial, no = null;
        var semi = rest.IndexOf(';');
        if (semi >= 0)
        {
            pat = rest[..semi];
            rest = rest[(semi + 1)..];
        }
        var dash = rest.IndexOf('-');
        if (dash >= 0)
        {
            ser = rest[..dash];
            rest = rest[(dash + 1)..];
        }
        var first = rest.Split(',', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
        var us = first.LastIndexOf('_');
        if (us >= 0 && us < first.Length - 1) no = first[(us + 1)..];
        return new(true, no, pat, ser, null, null);
    }

    static VnptResult ParseOk(RawResult raw)
    {
        if (raw.Error != null) return new(false, null, null, null, "EXCEPTION", raw.Error);
        var v = (raw.Value ?? "").Trim();
        if (v.StartsWith("OK", StringComparison.OrdinalIgnoreCase))
            return new(true, null, null, null, null, null);
        return new(false, null, null, null, v, ErrText(v) ?? $"VNPT từ chối: {Trim(v)}");
    }

    /// <summary>Bảng mã lỗi VNPT Invoice thường gặp.</summary>
    public static string? ErrText(string? raw)
    {
        var v = (raw ?? "").Trim();
        if (!v.StartsWith("ERR", StringComparison.OrdinalIgnoreCase)) return null;
        var code = v.Length > 4 ? v[4..].Split([':', ' ', ';'], 2)[0] : "";
        var msg = code switch
        {
            "1" => "Sai tài khoản / mật khẩu VNPT hoặc tài khoản không có quyền",
            "2" => "Hóa đơn không tồn tại trên VNPT (hoặc mẫu/ký hiệu không đúng)",
            "3" => "Dữ liệu XML hóa đơn không đúng định dạng VNPT",
            "5" => "VNPT không phát hành được hóa đơn — kiểm tra chữ ký số / dải số",
            "6" => "Dải hóa đơn VNPT đã hết số hoặc chưa có thông báo phát hành",
            "7" => "Sai tài khoản phát hành (username) VNPT",
            "8" => "Hóa đơn đã bị thay thế / hủy trước đó",
            "9" => "Trạng thái hóa đơn không cho phép thao tác này",
            "10" => "Số lượng hóa đơn trong lô vượt giới hạn",
            "13" => "Fkey đã tồn tại trên VNPT — dùng Đồng bộ",
            "20" => "Mẫu số (pattern) / ký hiệu (serial) VNPT không đúng hoặc chưa được cấp quyền",
            "21" => "Trùng số hóa đơn trên VNPT",
            _ => null,
        };
        return msg == null ? $"VNPT báo lỗi {v}" : $"{msg} ({v})";
    }

    static List<VnptListItem> ParseList(string xml)
    {
        var list = new List<VnptListItem>();
        if (string.IsNullOrWhiteSpace(xml) || !xml.TrimStart().StartsWith('<')) return list;
        try
        {
            var doc = XDocument.Parse(xml);
            foreach (var item in doc.Descendants().Where(e => e.Name.LocalName is "Item" or "Inv" or "Invoice"))
            {
                string? V(params string[] names) => names
                    .Select(n => item.Elements().FirstOrDefault(e =>
                        string.Equals(e.Name.LocalName, n, StringComparison.OrdinalIgnoreCase))?.Value)
                    .FirstOrDefault(s => !string.IsNullOrWhiteSpace(s))?.Trim();
                DateTime? date = DateTime.TryParse(V("publishDate", "ArisingDate", "PublishDate"), out var d) ? d : null;
                decimal.TryParse(V("amount", "Amount", "total"), System.Globalization.NumberStyles.Any,
                    System.Globalization.CultureInfo.InvariantCulture, out var amt);
                int.TryParse(V("status", "invStatus"), out var st);
                list.Add(new VnptListItem(
                    V("fkey", "key"),
                    V("invNum", "invoiceNo", "no"),
                    V("pattern"),
                    V("serial"),
                    date,
                    amt,
                    V("cusname", "cusName", "customerName"),
                    st));
            }
        }
        catch
        {
            // XML lạ — bỏ qua.
        }
        return list;
    }

    static string Trim(string? s)
    {
        s = (s ?? "").Replace('\n', ' ').Trim();
        return s.Length <= 400 ? s : s[..400];
    }
}
