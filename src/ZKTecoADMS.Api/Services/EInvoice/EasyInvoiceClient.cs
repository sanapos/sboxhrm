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
            return (true, "Xác thực Easy Invoice thành công");
        return (false, ping.Error ?? "Không xác thực được Easy Invoice");
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

            if (!res.IsSuccessStatusCode && status != 2)
            {
                if (LooksLikeAuthError(message, errorCode, body))
                    return (false, message ?? TrimErr(body), []);
                return (false, message ?? $"HTTP {(int)res.StatusCode}: {TrimErr(body)}", []);
            }

            if (status == 2)
                return (true, null, ReadInvoices(rootEl));

            if (LooksLikeAuthError(message, errorCode, body))
                return (false, message ?? errorCode ?? TrimErr(body), []);

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
                return new(false, null, null, null, null, null, errorCode ?? "FAIL", detail);
            }

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
        var t = $"{message} {errorCode} {body}".ToLowerInvariant();
        return t.Contains("xác thực") || t.Contains("xac thuc") ||
               t.Contains("authentication") || t.Contains("unauthorized") ||
               t.Contains("sai mật khẩu") || t.Contains("sai mat khau") ||
               t.Contains("invalid user") || t.Contains("unauthor");
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
