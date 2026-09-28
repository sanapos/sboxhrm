using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ZKTecoADMS.Api.Services.EInvoice;

public record EasyInvoiceResult(
    bool Ok,
    string? InvoiceNo,
    string? LookupCode,
    string? Pattern,
    string? Serial,
    string? TaxAuthorityCode,
    string? ErrorCode,
    string? Error);

public record EasyInvoiceListItem(
    string? Ikey,
    string? No,
    string? Pattern,
    string? Serial,
    string? LookupCode,
    string? ArisingDate,
    string? CustomerName,
    decimal Amount,
    int InvoiceStatus,
    string? LinkView);

/// <summary>
/// Easy Invoice v8 — token Authentication (kèm taxCode từ 01/01/2026)
/// + importAndIssueInvoice (ký server) + tra cứu theo ikey.
/// </summary>
public class EasyInvoiceClient(IHttpClientFactory httpFactory, ILogger<EasyInvoiceClient> logger)
{
    static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    public const string DefaultProdUrl = "https://api.easyinvoice.vn";
    public const string DefaultDemoUrl = "http://api.softdreams.vn";

    public static string NormalizeBaseUrl(string? raw)
    {
        var url = (raw ?? "").Trim();
        if (string.IsNullOrWhiteSpace(url))
            url = DefaultProdUrl;
        url = url.TrimEnd('/');
        return url;
    }

    public static string GenerateToken(string httpMethod, string username, string password, string taxCode)
    {
        var timestamp = Convert.ToUInt64(DateTimeOffset.UtcNow.ToUnixTimeSeconds()).ToString();
        var nonce = Guid.NewGuid().ToString("N").ToLowerInvariant();
        var signatureRaw = $"{httpMethod.ToUpperInvariant()}{timestamp}{nonce}";
        var hash = MD5.HashData(Encoding.UTF8.GetBytes(signatureRaw));
        var signature = Convert.ToBase64String(hash);
        return $"{signature}:{nonce}:{timestamp}:{username}:{password}:{taxCode}";
    }

    public async Task<(bool Ok, string Message)> TestConnectionAsync(
        string baseUrl, string username, string password, string taxCode, CancellationToken ct = default)
    {
        var ping = await GetInvoicesByIkeysAsync(
            baseUrl, username, password, taxCode, ["sbox-ping"], ct);
        if (ping.AuthOk)
            return (true,
                "Xác thực Easy Invoice thành công. Lưu ý: kiểm tra kết nối không tạo hóa đơn — " +
                "cần thanh toán đơn có chọn xuất HĐĐT. Pattern=mẫu số, Serial=ký hiệu (vd. 1 + C26MAA).");
        return (false, ping.Error ?? "Không xác thực được Easy Invoice");
    }

    public async Task<EasyInvoiceResult> ImportDraftAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        string xmlData,
        string pattern,
        string serial,
        CancellationToken ct = default)
    {
        return await PostPublishAsync(
            baseUrl, username, password, taxCode,
            "/api/publish/importInvoice",
            new { XmlData = xmlData, Pattern = pattern, Serial = serial },
            ct);
    }

    /// <summary>Phát hành hóa đơn nháp / chờ ký theo Ikeys (tài liệu v8: «issueInvoices», Pattern bắt buộc).</summary>
    public async Task<EasyInvoiceResult> IssueByIkeysAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        IReadOnlyList<string> ikeys,
        string pattern,
        string serial,
        CancellationToken ct = default)
    {
        var body = new { Ikeys = ikeys, Pattern = pattern, Serial = serial };
        var first = await PostPublishAsync(
            baseUrl, username, password, taxCode, "/api/publish/issueInvoices", body, ct);
        if (first.Ok || first.ErrorCode is "TIMEOUT") return first;
        // Bản API cũ dùng tên số ít.
        var legacy = await PostPublishAsync(
            baseUrl, username, password, taxCode, "/api/publish/issueInvoice", body, ct);
        return legacy.Ok ? legacy : first;
    }

    /// <summary>Thay thế hóa đơn đã phát hành (ký server) — Ikey = ikey HĐ gốc; XmlData chứa Ikey mới.</summary>
    public Task<EasyInvoiceResult> ReplaceAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        string originalIkey,
        string xmlData,
        string pattern,
        string serial,
        CancellationToken ct = default) =>
        PostPublishAsync(
            baseUrl, username, password, taxCode, "/api/business/replaceInvoice",
            new { Ikey = originalIkey, XmlData = xmlData, Pattern = pattern, Serial = serial },
            ct);

    /// <summary>Tải PDF hóa đơn (Option 0 = PDF thường).</summary>
    public async Task<(bool Ok, byte[]? Pdf, string? Error)> GetPdfAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        string ikey,
        string pattern,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("easy-invoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}/api/publish/getInvoicePdf");
        ApplyAuth(req, username, password, taxCode);
        req.Content = new StringContent(
            JsonSerializer.Serialize(new { Ikey = ikey, Pattern = pattern, Option = 0 }, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            return await ReadPdfResponseAsync(res, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Easy Invoice getInvoicePdf failed");
            return (false, null, ex.Message);
        }
    }

    /// <summary>PDF xem trước từ XmlData — không lưu trên Easy (previewInvoice, Option 1 = PDF).</summary>
    public async Task<(bool Ok, byte[]? Pdf, string? Error)> PreviewAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        string xmlData,
        string pattern,
        string serial,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("easy-invoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}/api/publish/previewInvoice");
        ApplyAuth(req, username, password, taxCode);
        req.Content = new StringContent(
            JsonSerializer.Serialize(new { XmlData = xmlData, Pattern = pattern, Serial = serial, Option = 1 }, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            return await ReadPdfResponseAsync(res, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Easy Invoice previewInvoice failed");
            return (false, null, ex.Message);
        }
    }

    /// <summary>Easy trả file PDF thô hoặc JSON { Data: base64 }.</summary>
    static async Task<(bool Ok, byte[]? Pdf, string? Error)> ReadPdfResponseAsync(
        HttpResponseMessage res, CancellationToken ct)
    {
        var bytes = await res.Content.ReadAsByteArrayAsync(ct);
        if (LooksLikePdf(bytes))
            return (true, bytes, null);
        try
        {
            var text = Encoding.UTF8.GetString(bytes);
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(text) ? "{}" : text);
            var rootEl = doc.RootElement;
            if (rootEl.ValueKind == JsonValueKind.Object &&
                (rootEl.TryGetProperty("Data", out var data) || rootEl.TryGetProperty("data", out data)))
            {
                var b64 = data.ValueKind switch
                {
                    JsonValueKind.String => data.GetString(),
                    JsonValueKind.Object => ReadString(data, "Pdf") ?? ReadString(data, "Base64") ??
                                            ReadString(data, "File") ?? ReadString(data, "FileData"),
                    _ => null,
                };
                if (!string.IsNullOrWhiteSpace(b64))
                {
                    var pdf = Convert.FromBase64String(b64);
                    if (LooksLikePdf(pdf)) return (true, pdf, null);
                }
            }
            return (false, null,
                ReadKeyInvoiceMsg(rootEl) ?? ReadString(rootEl, "Message") ??
                $"Easy Invoice không trả PDF (HTTP {(int)res.StatusCode})");
        }
        catch (Exception ex)
        {
            return (false, null, $"Easy Invoice trả dữ liệu PDF không hợp lệ: {ex.Message}");
        }
    }

    static bool LooksLikePdf(byte[] b) =>
        b.Length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46;

    /// <summary>Danh sách hóa đơn theo ngày lập (Option 1 = tất cả, kể cả lập trên portal).</summary>
    public async Task<(bool Ok, string? Error, int Total, List<EasyInvoiceListItem> Items)> ListByArisingDateAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        DateTime fromLocal,
        DateTime toLocal,
        int page,
        int pageSize,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("easy-invoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}/api/business/getInvoiceByArisingDateRange");
        ApplyAuth(req, username, password, taxCode);
        req.Content = new StringContent(
            JsonSerializer.Serialize(new
            {
                FromDate = fromLocal.ToString("dd/MM/yyyy"),
                ToDate = toLocal.ToString("dd/MM/yyyy"),
                Page = Math.Max(1, page),
                PageSize = Math.Clamp(pageSize, 1, 100),
                Option = 1,
            }, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            var rootEl = doc.RootElement;
            if (ReadStatus(rootEl) != 2)
                return (false, ReadString(rootEl, "Message") ?? $"HTTP {(int)res.StatusCode}: {TrimErr(body)}", 0, []);
            var total = 0;
            var items = new List<EasyInvoiceListItem>();
            if (TryGetData(rootEl, out var data) && data.ValueKind == JsonValueKind.Object)
            {
                int.TryParse(ReadString(data, "TotalRecords"), out total);
                if ((data.TryGetProperty("Invoices", out var arr) || data.TryGetProperty("invoices", out arr)) &&
                    arr.ValueKind == JsonValueKind.Array)
                {
                    foreach (var el in arr.EnumerateArray())
                    {
                        decimal.TryParse(ReadString(el, "Amount"), System.Globalization.NumberStyles.Any,
                            System.Globalization.CultureInfo.InvariantCulture, out var amt);
                        int.TryParse(ReadString(el, "InvoiceStatus"), out var st);
                        items.Add(new EasyInvoiceListItem(
                            ReadString(el, "Ikey"),
                            ReadString(el, "No"),
                            ReadString(el, "Pattern"),
                            ReadString(el, "Serial"),
                            ReadString(el, "LookupCode"),
                            ReadString(el, "ArisingDate"),
                            ReadString(el, "CustomerName") ?? ReadString(el, "Buyer"),
                            amt,
                            st,
                            ReadString(el, "LinkView")));
                    }
                }
            }
            return (true, null, total == 0 ? items.Count : total, items);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Easy Invoice getInvoiceByArisingDateRange failed");
            return (false, ex.Message, 0, []);
        }
    }

    public async Task<EasyInvoiceResult> CancelAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        string ikey,
        string pattern,
        string serial,
        CancellationToken ct = default)
    {
        var body = new { Ikey = ikey, Fkey = ikey, Pattern = pattern, Serial = serial };
        var first = await PostPublishAsync(
            baseUrl, username, password, taxCode, "/api/publish/cancelInvoice", body, ct);
        if (first.Ok) return first;
        return await PostPublishAsync(
            baseUrl, username, password, taxCode, "/api/business/cancelInvoice", body, ct);
    }

    public async Task<EasyInvoiceResult> SendMailAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        string ikey,
        string email,
        CancellationToken ct = default)
    {
        // Tài liệu v8: business/sendIssuanceNotice { IkeyEmail: { ikey: email } }.
        var notice = await PostPublishAsync(
            baseUrl, username, password, taxCode, "/api/business/sendIssuanceNotice",
            new { IkeyEmail = new Dictionary<string, string> { [ikey] = email.Trim() } }, ct);
        if (notice.Ok) return notice;
        var mails = new[] { email.Trim() };
        var payload = new { Ikeys = new[] { ikey }, Mails = mails, Emails = mails };
        var legacy = await PostPublishAsync(
            baseUrl, username, password, taxCode, "/api/publish/sendInvoiceByMail", payload, ct);
        return legacy.Ok ? legacy : notice;
    }

    async Task<EasyInvoiceResult> PostPublishAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        string path,
        object payload,
        CancellationToken ct)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("easy-invoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}{path}");
        ApplyAuth(req, username, password, taxCode);
        req.Content = new StringContent(
            JsonSerializer.Serialize(payload, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            return ParseIssueResponse(res.IsSuccessStatusCode, body);
        }
        catch (TaskCanceledException)
        {
            return new(false, null, null, null, null, null, "TIMEOUT",
                "Hết thời gian chờ Easy Invoice.");
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Easy Invoice POST {Path} failed", path);
            return new(false, null, null, null, null, null, "EXCEPTION", ex.Message);
        }
    }

    public async Task<EasyInvoiceResult> ImportAndIssueAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        string xmlData,
        string pattern,
        string serial,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("easy-invoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}/api/publish/importAndIssueInvoice");
        ApplyAuth(req, username, password, taxCode);
        req.Content = new StringContent(
            JsonSerializer.Serialize(new { XmlData = xmlData, Pattern = pattern, Serial = serial }, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            return ParseIssueResponse(res.IsSuccessStatusCode, body);
        }
        catch (TaskCanceledException)
        {
            return new(false, null, null, null, null, null, "TIMEOUT",
                "Hết thời gian chờ Easy Invoice. Thử xuất lại từ danh sách đơn.");
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Easy Invoice importAndIssueInvoice failed");
            return new(false, null, null, null, null, null, "EXCEPTION", ex.Message);
        }
    }

    public async Task<EasyInvoiceResult> LookupByIkeyAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        string ikey,
        CancellationToken ct = default)
    {
        var found = await GetInvoicesByIkeysAsync(baseUrl, username, password, taxCode, [ikey], ct);
        if (!found.AuthOk)
            return new(false, null, null, null, null, null, "LOOKUP", found.Error);
        if (found.Invoices.Count == 0)
            return new(false, null, null, null, null, null, "NOT_FOUND", "Chưa thấy hóa đơn Easy theo ikey");
        var inv = found.Invoices[0];
        return new(true, inv.No, inv.LookupCode, inv.Pattern, inv.Serial, inv.TaxAuthorityCode, null, null);
    }

    async Task<(bool AuthOk, string? Error, List<EasyInvoiceDto> Invoices)> GetInvoicesByIkeysAsync(
        string baseUrl,
        string username,
        string password,
        string taxCode,
        IReadOnlyList<string> ikeys,
        CancellationToken ct)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("easy-invoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}/api/publish/getInvoicesByIkeys");
        ApplyAuth(req, username, password, taxCode);
        req.Content = new StringContent(
            JsonSerializer.Serialize(new { Ikeys = ikeys }, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            if ((int)res.StatusCode is 401 or 403)
                return (false, $"HTTP {(int)res.StatusCode}: {TrimErr(body)}", []);

            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            var rootEl = doc.RootElement;
            var status = ReadStatus(rootEl);
            var message = ReadString(rootEl, "Message") ?? ReadString(rootEl, "message");
            var errorCode = ReadString(rootEl, "ErrorCode") ?? ReadString(rootEl, "errorCode");

            // SoftDreams hay trả HTTP 404 kèm JSON Status/ErrorCode khi ikey không có —
            // miễn không phải lỗi xác thực thì coi token hợp lệ.
            if (LooksLikeAuthError(message, errorCode, body))
                return (false, message ?? errorCode ?? TrimErr(body), []);

            if (status == 2)
                return (true, null, ReadInvoices(rootEl));

            if (!res.IsSuccessStatusCode && status == 0 && string.IsNullOrWhiteSpace(message))
                return (false, $"HTTP {(int)res.StatusCode}: {TrimErr(body)}", []);

            // Lỗi nghiệp vụ (ikey không tồn tại…) — token vẫn hợp lệ.
            return (true, message, ReadInvoices(rootEl));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Easy Invoice getInvoicesByIkeys failed");
            return (false, ex.Message, []);
        }
    }

    static void ApplyAuth(HttpRequestMessage req, string username, string password, string taxCode)
    {
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Headers.TryAddWithoutValidation(
            "Authentication", GenerateToken("POST", username, password, taxCode));
    }

    static EasyInvoiceResult ParseIssueResponse(bool httpOk, string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            var root = doc.RootElement;
            var status = ReadStatus(root);
            var message = ReadString(root, "Message") ?? ReadString(root, "message");
            var errorCode = ReadString(root, "ErrorCode") ?? ReadString(root, "errorCode");

            if (status != 2)
            {
                var detail = ReadKeyInvoiceMsg(root) ?? message ?? TrimErr(body);
                if ((errorCode ?? "").Trim() == "117" ||
                    (detail?.Contains("không khả dụng", StringComparison.OrdinalIgnoreCase) ?? false))
                {
                    detail =
                        "Easy Invoice từ chối mẫu (Error 117). " +
                        "Với mẫu MTT kiểu «1C26MAA» (hóa đơn máy tính tiền): API publish SoftDreams thường không nhận — " +
                        "dù portal còn số MTT. Cần SoftDreams bật tích hợp API cho mẫu MTT, hoặc đăng ký thêm mẫu HĐ thường cho API. " +
                        "Kiểm tra portal: Còn lại MTT/HĐ thường; Pattern đúng cột Mẫu số; Serial để trống nếu portal trống. " +
                        $"Chi tiết: {detail}";
                }
                return new(false, null, null, null, null, null, errorCode ?? "FAIL", detail);
            }

            // sendIssuanceNotice: Status 2 nhưng KeyInvoiceMsg từng ikey có thể báo «Lỗi, …».
            var perKey = ReadKeyInvoiceMsg(root);
            if (perKey != null && perKey.Contains("Lỗi", StringComparison.OrdinalIgnoreCase) &&
                !perKey.Contains("Thành công", StringComparison.OrdinalIgnoreCase))
                return new(false, null, null, null, null, null, errorCode ?? "FAIL", perKey);

            var invoices = ReadInvoices(root);
            EasyInvoiceDto? first = invoices.Count > 0 ? invoices[0] : null;
            var no = first?.No ?? ReadKeyInvoiceNo(root);
            return new(
                true,
                no,
                first?.LookupCode,
                first?.Pattern,
                first?.Serial,
                first?.TaxAuthorityCode,
                null,
                string.IsNullOrWhiteSpace(no) ? "Đã phát hành Easy — chờ số hóa đơn" : null);
        }
        catch
        {
            if (!httpOk)
                return new(false, null, null, null, null, null, "HTTP", TrimErr(body));
            return new(false, null, null, null, null, null, "PARSE", TrimErr(body));
        }
    }

    static List<EasyInvoiceDto> ReadInvoices(JsonElement root)
    {
        var list = new List<EasyInvoiceDto>();
        if (!TryGetData(root, out var data)) return list;
        if (!data.TryGetProperty("Invoices", out var arr) && !data.TryGetProperty("invoices", out arr))
            return list;
        if (arr.ValueKind != JsonValueKind.Array) return list;
        foreach (var el in arr.EnumerateArray())
        {
            list.Add(new EasyInvoiceDto(
                ReadString(el, "No") ?? ReadString(el, "no"),
                ReadString(el, "LookupCode") ?? ReadString(el, "lookupCode"),
                ReadString(el, "Pattern") ?? ReadString(el, "pattern"),
                ReadString(el, "Serial") ?? ReadString(el, "serial"),
                ReadString(el, "TaxAuthorityCode") ?? ReadString(el, "taxAuthorityCode"),
                ReadString(el, "Ikey") ?? ReadString(el, "ikey")));
        }
        return list;
    }

    static string? ReadKeyInvoiceNo(JsonElement root)
    {
        if (!TryGetData(root, out var data)) return null;
        if (!data.TryGetProperty("KeyInvoiceNo", out var dict) &&
            !data.TryGetProperty("keyInvoiceNo", out dict))
            return null;
        if (dict.ValueKind != JsonValueKind.Object) return null;
        foreach (var p in dict.EnumerateObject())
        {
            var v = p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString() : p.Value.ToString();
            if (!string.IsNullOrWhiteSpace(v)) return v;
        }
        return null;
    }

    static string? ReadKeyInvoiceMsg(JsonElement root)
    {
        if (!TryGetData(root, out var data)) return null;
        if (!data.TryGetProperty("KeyInvoiceMsg", out var dict) &&
            !data.TryGetProperty("keyInvoiceMsg", out dict))
            return null;
        if (dict.ValueKind != JsonValueKind.Object) return null;
        var parts = new List<string>();
        foreach (var p in dict.EnumerateObject())
        {
            var v = p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString() : p.Value.ToString();
            if (!string.IsNullOrWhiteSpace(v))
                parts.Add($"{p.Name}: {v}");
        }
        return parts.Count == 0 ? null : string.Join("; ", parts);
    }

    static bool TryGetData(JsonElement root, out JsonElement data)
    {
        if (root.TryGetProperty("Data", out data) || root.TryGetProperty("data", out data))
            return data.ValueKind is JsonValueKind.Object or JsonValueKind.Array;
        data = default;
        return false;
    }

    static int ReadStatus(JsonElement root)
    {
        if (!root.TryGetProperty("Status", out var s) && !root.TryGetProperty("status", out s))
            return 0;
        if (s.ValueKind == JsonValueKind.Number && s.TryGetInt32(out var n)) return n;
        if (s.ValueKind == JsonValueKind.String && int.TryParse(s.GetString(), out n)) return n;
        return 0;
    }

    static string? ReadString(JsonElement el, string name)
    {
        if (!el.TryGetProperty(name, out var p)) return null;
        return p.ValueKind switch
        {
            JsonValueKind.String => p.GetString(),
            JsonValueKind.Number => p.ToString(),
            JsonValueKind.Null => null,
            _ => p.ToString(),
        };
    }

    static bool LooksLikeAuthError(string? message, string? errorCode, string body)
    {
        var code = (errorCode ?? "").Trim();
        // SoftDreams: 177 tài khoản/MK sai; 176 hệ thống demo chưa khởi tạo; 175…
        if (code is "177" or "176" or "175") return true;

        var t = $"{message} {errorCode} {body}".ToLowerInvariant();
        return t.Contains("xác thực") || t.Contains("xac thuc") ||
               t.Contains("authentication") || t.Contains("unauthorized") ||
               t.Contains("sai mật khẩu") || t.Contains("sai mat khau") ||
               t.Contains("invalid user") || t.Contains("unauthor") ||
               t.Contains("không hợp lệ") || t.Contains("khong hop le") ||
               t.Contains("chưa được kích hoạt") || t.Contains("chua duoc kich hoat") ||
               t.Contains("hệ thống chưa được khởi tạo") || t.Contains("he thong chua");
    }

    static string TrimErr(string body)
    {
        body = (body ?? "").Trim();
        return body.Length <= 400 ? body : body[..400];
    }

    sealed record EasyInvoiceDto(
        string? No,
        string? LookupCode,
        string? Pattern,
        string? Serial,
        string? TaxAuthorityCode,
        string? Ikey);
}
