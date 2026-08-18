using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Caching.Memory;

namespace ZKTecoADMS.Api.Services.EInvoice;

public record ViettelLoginResult(bool Ok, string? AccessToken, string? Error);

public record ViettelCreateResult(
    bool Ok,
    string? InvoiceNo,
    string? ReservationCode,
    string? TransactionId,
    string? CodeOfTax,
    string? ErrorCode,
    string? Error);

/// <summary>Client Viettel SInvoice v2.46 — login token + createInvoice + tra cứu UUID.</summary>
public class ViettelSInvoiceClient(IHttpClientFactory httpFactory, IMemoryCache cache, ILogger<ViettelSInvoiceClient> logger)
{
    static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    public static string NormalizeBaseUrl(string? raw)
    {
        var url = (raw ?? "").Trim();
        if (string.IsNullOrWhiteSpace(url))
            url = "https://api-vinvoice.viettel.vn";
        url = url.TrimEnd('/');
        const string apiSuffix = "/services/einvoiceapplication/api";
        if (url.EndsWith(apiSuffix, StringComparison.OrdinalIgnoreCase))
            url = url[..^apiSuffix.Length];
        return url;
    }

    public async Task<ViettelLoginResult> LoginAsync(
        string baseUrl, string username, string password, CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("viettel-sinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}/auth/login");
        req.Content = new StringContent(
            JsonSerializer.Serialize(new { username, password }, JsonOpts),
            Encoding.UTF8,
            "application/json");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            if (!res.IsSuccessStatusCode)
                return new(false, null, $"Login HTTP {(int)res.StatusCode}: {TrimErr(body)}");
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            var token = ReadToken(doc.RootElement);
            if (string.IsNullOrWhiteSpace(token))
                return new(false, null, "Đăng nhập Viettel thành công nhưng không có access_token");
            return new(true, token, null);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Viettel SInvoice login failed");
            return new(false, null, ex.Message);
        }
    }

    public async Task<string> GetAccessTokenAsync(
        Guid storeId, string baseUrl, string username, string password, CancellationToken ct = default)
    {
        var cacheKey = $"viettel-sinvoice-token:{storeId:N}";
        if (cache.TryGetValue(cacheKey, out string? cached) && !string.IsNullOrWhiteSpace(cached))
            return cached;

        var login = await LoginAsync(baseUrl, username, password, ct);
        if (!login.Ok || string.IsNullOrWhiteSpace(login.AccessToken))
            throw new InvalidOperationException(login.Error ?? "Không đăng nhập được Viettel SInvoice");

        cache.Set(
            cacheKey,
            login.AccessToken,
            new MemoryCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(50),
                Size = 1,
            });
        return login.AccessToken;
    }

    public void InvalidateToken(Guid storeId) =>
        cache.Remove($"viettel-sinvoice-token:{storeId:N}");

    public async Task<ViettelCreateResult> CreateInvoiceAsync(
        string baseUrl,
        string accessToken,
        string supplierTaxCode,
        object payload,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var tax = Uri.EscapeDataString(supplierTaxCode.Trim());
        var url = $"{root}/services/einvoiceapplication/api/InvoiceAPI/InvoiceWS/createInvoice/{tax}";
        return await PostInvoiceAsync(url, accessToken, payload, ct);
    }

    /// <summary>Tạo hóa đơn nháp (chờ ký) khi tài khoản chưa gắn chứng thư số.</summary>
    public async Task<ViettelCreateResult> CreateInvoiceDraftAsync(
        string baseUrl,
        string accessToken,
        string supplierTaxCode,
        object payload,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var tax = Uri.EscapeDataString(supplierTaxCode.Trim());
        var url = $"{root}/services/einvoiceapplication/api/InvoiceAPI/InvoiceWS/createOrUpdateInvoiceDraft/{tax}";
        var created = await PostInvoiceAsync(url, accessToken, payload, ct);
        if (created.Ok) return created;

        // Draft đôi khi trả result rỗng — tra cứu theo transactionUuid trong payload.
        if (TryReadTransactionUuid(payload, out var uuid) && !string.IsNullOrWhiteSpace(uuid))
        {
            var found = await SearchByTransactionUuidAsync(baseUrl, accessToken, supplierTaxCode, uuid, ct);
            if (found.Ok) return found;
        }
        return created;
    }

    async Task<ViettelCreateResult> PostInvoiceAsync(
        string url, string accessToken, object payload, CancellationToken ct)
    {
        var client = httpFactory.CreateClient("viettel-sinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("Cookie", $"access_token={accessToken}");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new StringContent(
            JsonSerializer.Serialize(payload, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            return ParseCreateResponse(res.IsSuccessStatusCode, body);
        }
        catch (TaskCanceledException)
        {
            return new(false, null, null, null, null, "TIMEOUT", "Hết thời gian chờ Viettel (khuyến nghị 60–90s). Thử xuất lại từ danh sách đơn.");
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Viettel invoice POST failed: {Url}", url);
            return new(false, null, null, null, null, "EXCEPTION", ex.Message);
        }
    }

    static bool TryReadTransactionUuid(object payload, out string? uuid)
    {
        uuid = null;
        try
        {
            using var doc = JsonDocument.Parse(JsonSerializer.Serialize(payload, JsonOpts));
            if (doc.RootElement.TryGetProperty("generalInvoiceInfo", out var gi) &&
                gi.TryGetProperty("transactionUuid", out var u) &&
                u.ValueKind == JsonValueKind.String)
            {
                uuid = u.GetString();
                return !string.IsNullOrWhiteSpace(uuid);
            }
        }
        catch { /* ignore */ }
        return false;
    }

    public async Task<ViettelCreateResult> SearchByTransactionUuidAsync(
        string baseUrl,
        string accessToken,
        string supplierTaxCode,
        string transactionUuid,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var url = $"{root}/services/einvoiceapplication/api/InvoiceAPI/InvoiceWS/searchInvoiceByTransactionUuid";
        var client = httpFactory.CreateClient("viettel-sinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("Cookie", $"access_token={accessToken}");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["supplierTaxCode"] = supplierTaxCode.Trim(),
            ["transactionUuid"] = transactionUuid.Trim(),
        });
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            return ParseCreateResponse(res.IsSuccessStatusCode, body);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Viettel searchInvoiceByTransactionUuid failed");
            return new(false, null, null, null, null, "EXCEPTION", ex.Message);
        }
    }

    static ViettelCreateResult ParseCreateResponse(bool httpOk, string body)
    {
        if (string.IsNullOrWhiteSpace(body))
            return new(false, null, null, null, null, "EMPTY", httpOk ? "Viettel không trả dữ liệu" : "Lỗi HTTP Viettel");

        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            var errorCode = Str(root, "errorCode");
            if (string.IsNullOrWhiteSpace(errorCode) &&
                root.TryGetProperty("code", out var codeEl) &&
                codeEl.ValueKind == JsonValueKind.String)
                errorCode = codeEl.GetString();
            // HTTP body Viettel hay dùng message=SIGNATURE_NOT_FOUND, code=400 (số) — lấy message làm mã.
            var description = Str(root, "description") ?? Str(root, "message") ?? Str(root, "data");
            if (string.IsNullOrWhiteSpace(errorCode) &&
                !string.IsNullOrWhiteSpace(description) &&
                description.Contains('_', StringComparison.Ordinal) &&
                description.Length <= 80 &&
                description == description.ToUpperInvariant())
                errorCode = description;
            JsonElement result = default;
            var hasResult = root.TryGetProperty("result", out result) &&
                            result.ValueKind is JsonValueKind.Object or JsonValueKind.Array;

            JsonElement item = result;
            if (hasResult && result.ValueKind == JsonValueKind.Array && result.GetArrayLength() > 0)
                item = result[0];

            string? invoiceNo = null, reservation = null, transId = null, codeOfTax = null;
            if (hasResult && item.ValueKind == JsonValueKind.Object)
            {
                invoiceNo = Str(item, "invoiceNo");
                reservation = Str(item, "reservationCode");
                transId = Str(item, "transactionID") ?? Str(item, "transactionId");
                codeOfTax = Str(item, "codeOfTax");
            }

            var ok = string.IsNullOrWhiteSpace(errorCode) &&
                     (httpOk || !string.IsNullOrWhiteSpace(invoiceNo) || !string.IsNullOrWhiteSpace(reservation));
            if (!ok)
                return new(false, invoiceNo, reservation, transId, codeOfTax, errorCode, TrimErr(description ?? body));
            return new(true, invoiceNo, reservation, transId, codeOfTax, null, null);
        }
        catch
        {
            return new(false, null, null, null, null, "PARSE", TrimErr(body));
        }
    }

    static string? ReadToken(JsonElement root)
    {
        var t = Str(root, "access_token") ?? Str(root, "accessToken");
        if (!string.IsNullOrWhiteSpace(t)) return t;
        if (root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Object)
            return Str(data, "access_token") ?? Str(data, "accessToken");
        return null;
    }

    static string? Str(JsonElement el, string name)
    {
        if (el.ValueKind != JsonValueKind.Object) return null;
        if (!el.TryGetProperty(name, out var p)) return null;
        if (p.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return null;
        var s = p.ToString();
        return string.IsNullOrWhiteSpace(s) ? null : s.Trim();
    }

    static string TrimErr(string s)
    {
        s = s.Replace('\n', ' ').Trim();
        return s.Length <= 800 ? s : s[..800];
    }
}
