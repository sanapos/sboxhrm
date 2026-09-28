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

public record ViettelActionResult(bool Ok, string? ErrorCode, string? Error);

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

    public async Task<ViettelActionResult> CancelInvoiceAsync(
        string baseUrl,
        string accessToken,
        string supplierTaxCode,
        string invoiceNo,
        DateTime issuedAtUtc,
        string agreementDesc,
        DateTime agreementDateUtc,
        string? reason,
        string? templateCode = null,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var url = $"{root}/services/einvoiceapplication/api/InvoiceAPI/InvoiceWS/cancelTransactionInvoice";
        var issueMs = new DateTimeOffset(DateTime.SpecifyKind(issuedAtUtc, DateTimeKind.Utc))
            .ToUnixTimeMilliseconds()
            .ToString();
        var agree = DateTime.SpecifyKind(agreementDateUtc, DateTimeKind.Utc)
            .AddHours(7)
            .ToString("yyyyMMddHHmmss");
        var form = new Dictionary<string, string>
        {
            ["supplierTaxCode"] = supplierTaxCode.Trim(),
            ["invoiceNo"] = invoiceNo.Trim(),
            ["strIssueDate"] = issueMs,
            ["additionalReferenceDesc"] = string.IsNullOrWhiteSpace(agreementDesc)
                ? "Hủy hóa đơn theo thỏa thuận"
                : agreementDesc.Trim(),
            ["additionalReferenceDate"] = agree,
        };
        if (!string.IsNullOrWhiteSpace(templateCode))
            form["templateCode"] = templateCode.Trim();
        if (!string.IsNullOrWhiteSpace(reason))
            form["reasonDelete"] = reason.Trim();

        var client = httpFactory.CreateClient("viettel-sinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("Cookie", $"access_token={accessToken}");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new FormUrlEncodedContent(form);
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            return ParseActionResponse(res.IsSuccessStatusCode, body);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Viettel cancelTransactionInvoice failed");
            return new(false, "EXCEPTION", ex.Message);
        }
    }

    public async Task<ViettelActionResult> SendHtmlMailAsync(
        string baseUrl,
        string accessToken,
        string supplierTaxCode,
        string transactionUuid,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var url = $"{root}/services/einvoiceapplication/api/InvoiceAPI/InvoiceUtilsWS/sendHtmlMailProcess";
        var client = httpFactory.CreateClient("viettel-sinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("Cookie", $"access_token={accessToken}");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new StringContent(
            JsonSerializer.Serialize(new
            {
                supplierTaxCode = supplierTaxCode.Trim(),
                lstTransactionUuid = transactionUuid.Trim(),
            }, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            return ParseActionResponse(res.IsSuccessStatusCode, body);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Viettel sendHtmlMailProcess failed");
            return new(false, "EXCEPTION", ex.Message);
        }
    }

    /// <summary>File thể hiện hóa đơn (PDF) — getInvoiceRepresentationFile.</summary>
    public async Task<(bool Ok, byte[]? File, string? FileName, string? Error)> GetInvoiceFileAsync(
        string baseUrl,
        string accessToken,
        string supplierTaxCode,
        string invoiceNo,
        string templateCode,
        string? transactionUuid,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var url = $"{root}/services/einvoiceapplication/api/InvoiceAPI/InvoiceUtilsWS/getInvoiceRepresentationFile";
        var client = httpFactory.CreateClient("viettel-sinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("Cookie", $"access_token={accessToken}");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new StringContent(
            JsonSerializer.Serialize(new
            {
                supplierTaxCode = supplierTaxCode.Trim(),
                invoiceNo = invoiceNo.Trim(),
                templateCode = templateCode.Trim(),
                transactionUuid = string.IsNullOrWhiteSpace(transactionUuid) ? null : transactionUuid.Trim(),
                fileType = "PDF",
            }, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            var rootEl = doc.RootElement;
            var err = Str(rootEl, "errorCode");
            var b64 = Str(rootEl, "fileToBytes");
            if (!string.IsNullOrWhiteSpace(err) || string.IsNullOrWhiteSpace(b64))
                return (false, null, null, TrimErr(Str(rootEl, "description") ?? err ?? body));
            return (true, Convert.FromBase64String(b64), Str(rootEl, "fileName"), null);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Viettel getInvoiceRepresentationFile failed");
            return (false, null, null, ex.Message);
        }
    }

    /// <summary>PDF xem trước từ dữ liệu lập hóa đơn — Viettel không lưu (createInvoiceDraftPreview).</summary>
    public async Task<(bool Ok, byte[]? File, string? Error)> PreviewDraftAsync(
        string baseUrl,
        string accessToken,
        string supplierTaxCode,
        object payload,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var tax = Uri.EscapeDataString(supplierTaxCode.Trim());
        var url = $"{root}/services/einvoiceapplication/api/InvoiceAPI/InvoiceUtilsWS/createInvoiceDraftPreview/{tax}";
        var client = httpFactory.CreateClient("viettel-sinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("Cookie", $"access_token={accessToken}");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new StringContent(JsonSerializer.Serialize(payload, JsonOpts), Encoding.UTF8, "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            var rootEl = doc.RootElement;
            var err = Str(rootEl, "errorCode");
            var b64 = Str(rootEl, "fileToBytes");
            if (!string.IsNullOrWhiteSpace(err) || string.IsNullOrWhiteSpace(b64))
                return (false, null, TrimErr(Str(rootEl, "description") ?? err ?? body));
            return (true, Convert.FromBase64String(b64), null);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Viettel createInvoiceDraftPreview failed");
            return (false, null, ex.Message);
        }
    }

    public record ViettelInvoiceItem(
        string? InvoiceNo,
        string? TemplateCode,
        string? InvoiceSeri,
        DateTime? IssueDate,
        decimal Total,
        decimal TaxAmount,
        string? BuyerName,
        string? BuyerTaxCode,
        string? AdjustmentType,
        string? OriginalInvoiceId);

    /// <summary>Tra cứu danh sách hóa đơn theo ngày lập (getInvoices) — tối đa ~3 tháng / lần.</summary>
    public async Task<(bool Ok, string? Error, int Total, List<ViettelInvoiceItem> Items)> GetInvoicesAsync(
        string baseUrl,
        string accessToken,
        string supplierTaxCode,
        DateTime fromLocal,
        DateTime toLocal,
        int page,
        int pageSize,
        CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var tax = Uri.EscapeDataString(supplierTaxCode.Trim());
        var url = $"{root}/services/einvoiceapplication/api/InvoiceAPI/InvoiceUtilsWS/getInvoices/{tax}";
        var client = httpFactory.CreateClient("viettel-sinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("Cookie", $"access_token={accessToken}");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new StringContent(
            JsonSerializer.Serialize(new
            {
                startDate = fromLocal.ToString("yyyy-MM-dd"),
                endDate = toLocal.ToString("yyyy-MM-dd"),
                rowPerPage = Math.Clamp(pageSize, 1, 200),
                pageNum = Math.Max(1, page),
            }, JsonOpts),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            var rootEl = doc.RootElement;
            var err = Str(rootEl, "errorCode");
            if (!string.IsNullOrWhiteSpace(err) || !res.IsSuccessStatusCode)
                return (false, TrimErr(Str(rootEl, "description") ?? err ?? body), 0, []);
            int.TryParse(Str(rootEl, "totalRow"), out var total);
            var items = new List<ViettelInvoiceItem>();
            if (rootEl.TryGetProperty("invoices", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var it in arr.EnumerateArray())
                {
                    DateTime? issued = long.TryParse(Str(it, "issueDate"), out var ms)
                        ? DateTimeOffset.FromUnixTimeMilliseconds(ms).UtcDateTime
                        : null;
                    items.Add(new ViettelInvoiceItem(
                        Str(it, "invoiceNo"),
                        Str(it, "templateCode"),
                        Str(it, "invoiceSeri"),
                        issued,
                        Dec(it, "total"),
                        Dec(it, "taxAmount"),
                        Str(it, "buyerName"),
                        Str(it, "buyerTaxCode"),
                        Str(it, "adjustmentType"),
                        Str(it, "originalInvoiceId")));
                }
            }
            return (true, null, total == 0 ? items.Count : total, items);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Viettel getInvoices failed");
            return (false, ex.Message, 0, []);
        }
    }

    static decimal Dec(JsonElement el, string name) =>
        decimal.TryParse(Str(el, name), System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : 0;

    static ViettelActionResult ParseActionResponse(bool httpOk, string body)
    {
        if (string.IsNullOrWhiteSpace(body))
            return new(httpOk, httpOk ? null : "EMPTY", httpOk ? null : "Viettel không trả dữ liệu");
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            var errorCode = Str(root, "errorCode");
            var description = Str(root, "description") ?? Str(root, "message");
            var ok = string.IsNullOrWhiteSpace(errorCode) &&
                     (httpOk ||
                      (description?.Contains("SUCCESS", StringComparison.OrdinalIgnoreCase) ?? false));
            if (!ok)
                return new(false, errorCode, TrimErr(description ?? body));
            return new(true, null, description);
        }
        catch
        {
            return new(false, "PARSE", TrimErr(body));
        }
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
