using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Caching.Memory;

namespace ZKTecoADMS.Api.Services.EInvoice;

public record MisaPublishResult(
    bool Ok,
    string? TransactionId,
    string? InvoiceNo,
    string? InvoiceSeries,
    string? InvoiceCode,
    DateTime? InvoiceDate,
    string? ErrorCode,
    string? Error);

public record MisaStatusResult(
    bool Ok,
    string? TransactionId,
    int PublishStatus,
    int ReferenceType,
    string? InvoiceCode,
    int SendTaxStatus,
    bool IsSentEmail,
    bool IsDeleted,
    string? DeletedReason,
    string? Error);

/// <summary>
/// MISA meInvoice — Open API tích hợp (doc.meinvoice.vn/itg):
/// token (appid + MST + tài khoản) → phát hành ký HSM (SignType=2) / HĐ máy tính tiền (SignType=5),
/// xem (publishview), tải PDF (Download), gửi email, hủy, tra trạng thái.
/// </summary>
public class MisaMeInvoiceClient(IHttpClientFactory httpFactory, IMemoryCache cache, ILogger<MisaMeInvoiceClient> logger)
{
    public const string DefaultProdUrl = "https://api.meinvoice.vn/api/integration";
    public const string DefaultTestUrl = "https://testapi.meinvoice.vn/api/integration";

    static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    /// <summary>Chuẩn hóa về gốc «…/api/integration» (người dùng có thể dán cả «/invoice»).</summary>
    public static string NormalizeBaseUrl(string? raw)
    {
        var url = (raw ?? "").Trim().TrimEnd('/');
        if (string.IsNullOrWhiteSpace(url) ||
            url.Contains("viettel", StringComparison.OrdinalIgnoreCase) ||
            url.Contains("easyinvoice", StringComparison.OrdinalIgnoreCase) ||
            url.Contains("softdreams", StringComparison.OrdinalIgnoreCase) ||
            url.Contains("vnpt", StringComparison.OrdinalIgnoreCase))
            return DefaultProdUrl;
        if (url.EndsWith("/invoice", StringComparison.OrdinalIgnoreCase))
            url = url[..^"/invoice".Length];
        if (!url.Contains("/api/", StringComparison.OrdinalIgnoreCase))
            url += "/api/integration";
        return url;
    }

    static string CacheKey(Guid storeId) => $"misa-meinvoice-token:{storeId:N}";

    public void InvalidateToken(Guid storeId) => cache.Remove(CacheKey(storeId));

    public async Task<(bool Ok, string? Token, string? Error)> LoginAsync(
        string baseUrl, string appId, string taxCode, string username, string password, CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("misa-meinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}/auth/token");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Content = new StringContent(
            JsonSerializer.Serialize(new
            {
                appid = appId.Trim(),
                taxcode = taxCode.Trim(),
                username = username.Trim(),
                password,
            }),
            Encoding.UTF8,
            "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            var env = ParseEnvelope(body);
            if (env.Success && env.Data is { ValueKind: JsonValueKind.String } d &&
                !string.IsNullOrWhiteSpace(d.GetString()))
                return (true, d.GetString(), null);
            return (false, null, DescribeError(env.ErrorCode, env.Description, body, res));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "MISA meInvoice login failed");
            return (false, null, ex.Message);
        }
    }

    public async Task<string> GetTokenAsync(
        Guid storeId, string baseUrl, string appId, string taxCode, string username, string password,
        CancellationToken ct = default)
    {
        if (cache.TryGetValue(CacheKey(storeId), out string? cached) && !string.IsNullOrWhiteSpace(cached))
            return cached;
        var login = await LoginAsync(baseUrl, appId, taxCode, username, password, ct);
        if (!login.Ok || string.IsNullOrWhiteSpace(login.Token))
            throw new InvalidOperationException(login.Error ?? "Không đăng nhập được MISA meInvoice");
        // Token MISA sống ~14 ngày; cache ngắn cho an toàn khi đổi mật khẩu.
        cache.Set(CacheKey(storeId), login.Token, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(6),
            Size = 1,
        });
        return login.Token!;
    }

    /// <summary>Phát hành 1 hóa đơn (SignType 2 = HSM, 5 = máy tính tiền).</summary>
    public async Task<MisaPublishResult> PublishAsync(
        string baseUrl, string token, string taxCode, int signType, object invoiceData, CancellationToken ct = default)
    {
        var (ok, body, status) = await PostAsync(
            baseUrl, "/invoice", token, taxCode,
            new { SignType = signType, InvoiceData = new[] { invoiceData }, PublishInvoiceData = (object?)null },
            ct);
        if (status == 0)
            return new(false, null, null, null, null, null, "EXCEPTION", body);
        if (status == -1)
            return new(false, null, null, null, null, null, "TIMEOUT", "Hết thời gian chờ MISA meInvoice. Thử đồng bộ lại.");
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            var root = doc.RootElement;
            var success = ReadBool(root, "success");
            var errorCode = ReadStr(root, "errorCode");
            var desc = ReadStr(root, "descriptionErrorCode");
            var items = ReadJsonArray(root, "publishInvoiceResult");
            var first = items.Count > 0 ? items[0] : default;
            var itemErr = first.ValueKind == JsonValueKind.Object ? ReadStr(first, "ErrorCode") : null;
            if (!success || !string.IsNullOrWhiteSpace(errorCode) || !string.IsNullOrWhiteSpace(itemErr))
            {
                var code = FirstNonEmpty(itemErr, errorCode, "FAIL");
                return new(false, null, null, null, null, null, code,
                    MisaErrorText(code) ?? FirstNonEmpty(desc, Trim(body)));
            }
            if (first.ValueKind != JsonValueKind.Object)
                return new(false, null, null, null, null, null, "EMPTY", "MISA không trả kết quả phát hành");

            DateTime? invDate = null;
            if (DateTime.TryParse(ReadStr(first, "InvDate"), out var d)) invDate = d;
            return new(
                true,
                ReadStr(first, "TransactionID"),
                ReadStr(first, "InvNo"),
                ReadStr(first, "InvSeries"),
                ReadStr(first, "InvCode"),
                invDate,
                null,
                null);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "MISA publish parse failed");
            return new(false, null, null, null, null, null, "PARSE", Trim(body));
        }
    }

    /// <summary>Trạng thái theo RefID (inputType=2) hoặc TransactionID (inputType=1).</summary>
    public async Task<List<MisaStatusResult>> GetStatusAsync(
        string baseUrl, string token, string taxCode, IReadOnlyList<string> keys, bool byRefId,
        bool invoiceWithCode, bool cashRegister, CancellationToken ct = default)
    {
        var path = $"/invoice/status?invoiceWithCode={Lower(invoiceWithCode)}&invoiceCalcu={Lower(cashRegister)}&inputType={(byRefId ? 2 : 1)}";
        var (ok, body, status) = await PostAsync(baseUrl, path, token, taxCode, keys, ct);
        var list = new List<MisaStatusResult>();
        if (status <= 0) return list;
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            foreach (var it in ReadJsonArray(doc.RootElement, "data"))
            {
                if (it.ValueKind != JsonValueKind.Object) continue;
                list.Add(new MisaStatusResult(
                    true,
                    ReadStr(it, "TransactionID"),
                    ReadInt(it, "PublishStatus"),
                    ReadInt(it, "ReferenceType"),
                    ReadStr(it, "InvoiceCode"),
                    ReadInt(it, "SendTaxStatus"),
                    ReadBool(it, "IsSentEmail"),
                    ReadBool(it, "IsDelete"),
                    ReadStr(it, "DeletedReason"),
                    null));
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "MISA status parse failed");
        }
        return list;
    }

    public async Task<(bool Ok, string? Error)> CancelAsync(
        string baseUrl, string token, string taxCode, string transactionId, string invSeries, string reason,
        CancellationToken ct = default)
    {
        var (ok, body, status) = await PostAsync(baseUrl, "/invoice/cancel", token, taxCode, new
        {
            TransactionID = transactionId,
            InvSeries = invSeries,
            CancelReason = reason,
        }, ct);
        return ParseSimple(body, status, "MISA từ chối hủy hóa đơn");
    }

    public async Task<(bool Ok, string? Error)> SendEmailAsync(
        string baseUrl, string token, string taxCode, string transactionId, string receiverName, string email,
        bool invoiceWithCode, bool cashRegister, CancellationToken ct = default)
    {
        var (ok, body, status) = await PostAsync(baseUrl, "/invoice/sendemail", token, taxCode, new
        {
            SendEmailDatas = new[]
            {
                new { TransactionID = transactionId, ReceiverName = receiverName, ReceiverEmail = email },
            },
            IsInvoiceCode = invoiceWithCode,
            IsInvoiceCalculatingMachine = cashRegister,
        }, ct);
        var r = ParseSimple(body, status, "MISA từ chối gửi email");
        if (!r.Ok) return r;
        // data: [{ SendEmailStatus: 2 = lỗi, ErrorCode }]
        try
        {
            using var doc = JsonDocument.Parse(body);
            foreach (var it in ReadJsonArray(doc.RootElement, "data"))
            {
                if (it.ValueKind != JsonValueKind.Object) continue;
                var err = ReadStr(it, "ErrorCode");
                if (ReadInt(it, "SendEmailStatus") == 2 || !string.IsNullOrWhiteSpace(err))
                    return (false, MisaErrorText(err) ?? err ?? "MISA gửi email lỗi");
            }
        }
        catch { /* data không phải mảng → coi như OK */ }
        return (true, null);
    }

    /// <summary>Link xem PDF hóa đơn đã phát hành (hiệu lực ~5 phút).</summary>
    public async Task<(bool Ok, string? Url, string? Error)> GetViewUrlAsync(
        string baseUrl, string token, string taxCode, string transactionId, CancellationToken ct = default)
    {
        var (ok, body, status) = await PostAsync(
            baseUrl, "/invoice/publishview", token, taxCode, new[] { transactionId }, ct);
        var r = ParseSimple(body, status, "MISA không trả link xem hóa đơn");
        if (!r.Ok) return (false, null, r.Error);
        var env = ParseEnvelope(body);
        var url = env.Data is { ValueKind: JsonValueKind.String } d ? d.GetString() : null;
        return string.IsNullOrWhiteSpace(url)
            ? (false, null, "MISA không trả link xem hóa đơn")
            : (true, url, null);
    }

    /// <summary>Link PDF xem trước (chưa phát hành, hiệu lực ~30 giây) — unpublishview.</summary>
    public async Task<(bool Ok, string? Url, string? Error)> GetPreviewUrlAsync(
        string baseUrl, string token, string taxCode, object invoiceData, CancellationToken ct = default)
    {
        var (ok, body, status) = await PostAsync(baseUrl, "/invoice/unpublishview", token, taxCode, invoiceData, ct);
        var r = ParseSimple(body, status, "MISA không trả bản xem trước");
        if (!r.Ok) return (false, null, r.Error);
        var env = ParseEnvelope(body);
        var url = env.Data is { ValueKind: JsonValueKind.String } d ? d.GetString() : null;
        return string.IsNullOrWhiteSpace(url)
            ? (false, null, "MISA không trả bản xem trước")
            : (true, url, null);
    }

    /// <summary>Tải file từ link MISA (link xem chỉ sống vài chục giây → tải ngay về server).</summary>
    public async Task<byte[]?> TryDownloadAsync(string url, CancellationToken ct = default)
    {
        try
        {
            var client = httpFactory.CreateClient("misa-meinvoice");
            var bytes = await client.GetByteArrayAsync(url, ct);
            return bytes.Length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 ? bytes : null;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Tải PDF (base64) — dự phòng khi link xem hết hạn.</summary>
    public async Task<(bool Ok, byte[]? Pdf, string? Url, string? Error)> DownloadPdfAsync(
        string baseUrl, string token, string taxCode, string transactionId,
        bool invoiceWithCode, bool cashRegister, CancellationToken ct = default)
    {
        var path = $"/invoice/Download?invoiceWithCode={Lower(invoiceWithCode)}&invoiceCalcu={Lower(cashRegister)}&downloadDataType=Pdf";
        var (ok, body, status) = await PostAsync(baseUrl, path, token, taxCode, new[] { transactionId }, ct);
        var r = ParseSimple(body, status, "MISA không trả file hóa đơn");
        if (!r.Ok) return (false, null, null, r.Error);
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            // Tài liệu: data = [{TransactionID, Data(base64), ErrorCode}] — ví dụ lại trả link.
            if (TryGetCI(root, "data", out var data) && data.ValueKind == JsonValueKind.String)
            {
                var s = data.GetString() ?? "";
                if (s.StartsWith("http", StringComparison.OrdinalIgnoreCase))
                    return (true, null, s, null);
            }
            foreach (var it in ReadJsonArray(root, "data"))
            {
                if (it.ValueKind != JsonValueKind.Object) continue;
                var b64 = ReadStr(it, "Data") ?? ReadStr(it, "data");
                if (string.IsNullOrWhiteSpace(b64)) continue;
                return (true, Convert.FromBase64String(b64), null, null);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "MISA download parse failed");
        }
        return (false, null, null, "MISA không trả file hóa đơn");
    }

    public async Task<(bool Ok, string? Error, int Count)> GetTemplatesAsync(
        string baseUrl, string token, string taxCode, bool invoiceWithCode, CancellationToken ct = default)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("misa-meinvoice");
        using var req = new HttpRequestMessage(
            HttpMethod.Get,
            $"{root}/invoice/templates?invoiceWithCode={Lower(invoiceWithCode)}&ticket=false&year={DateTime.UtcNow.AddHours(7).Year}");
        ApplyAuth(req, token, taxCode);
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            var env = ParseEnvelope(body);
            if (!env.Success)
                return (false, DescribeError(env.ErrorCode, env.Description, body, res), 0);
            using var doc = JsonDocument.Parse(body);
            return (true, null, ReadJsonArray(doc.RootElement, "data").Count);
        }
        catch (Exception ex)
        {
            return (false, ex.Message, 0);
        }
    }

    async Task<(bool Ok, string Body, int Status)> PostAsync(
        string baseUrl, string path, string token, string taxCode, object payload, CancellationToken ct)
    {
        var root = NormalizeBaseUrl(baseUrl);
        var client = httpFactory.CreateClient("misa-meinvoice");
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{root}{path}");
        ApplyAuth(req, token, taxCode);
        req.Content = new StringContent(JsonSerializer.Serialize(payload, JsonOpts), Encoding.UTF8, "application/json");
        try
        {
            using var res = await client.SendAsync(req, ct);
            var body = await res.Content.ReadAsStringAsync(ct);
            return (res.IsSuccessStatusCode, body, (int)res.StatusCode);
        }
        catch (TaskCanceledException)
        {
            return (false, "Hết thời gian chờ MISA meInvoice", -1);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "MISA POST {Path} failed", path);
            return (false, ex.Message, 0);
        }
    }

    static void ApplyAuth(HttpRequestMessage req, string token, string taxCode)
    {
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        req.Headers.TryAddWithoutValidation("CompanyTaxCode", taxCode.Trim());
    }

    static (bool Ok, string? Error) ParseSimple(string body, int status, string fallback)
    {
        if (status == -1) return (false, "Hết thời gian chờ MISA meInvoice");
        if (status == 0) return (false, body);
        var env = ParseEnvelope(body);
        if (env.Success && string.IsNullOrWhiteSpace(env.ErrorCode)) return (true, null);
        if (status == 401) return (false, "Token MISA hết hạn / sai thông tin đăng nhập");
        return (false, MisaErrorText(env.ErrorCode) ?? FirstNonEmpty(env.Description, env.ErrorCode, Trim(body), fallback));
    }

    sealed record Envelope(bool Success, string? ErrorCode, string? Description, JsonElement? Data);

    static Envelope ParseEnvelope(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
            var root = doc.RootElement;
            JsonElement? data = TryGetCI(root, "data", out var d) ? d.Clone() : null;
            return new(
                ReadBool(root, "success"),
                ReadStr(root, "errorCode"),
                ReadStr(root, "descriptionErrorCode") ?? ReadErrors(root),
                data);
        }
        catch
        {
            return new(false, "PARSE", Trim(body), null);
        }
    }

    static string? ReadErrors(JsonElement root)
    {
        if (!TryGetCI(root, "errors", out var e) || e.ValueKind != JsonValueKind.Array) return null;
        var parts = e.EnumerateArray().Select(x => x.ToString()).Where(x => !string.IsNullOrWhiteSpace(x)).ToList();
        return parts.Count == 0 ? null : string.Join("; ", parts);
    }

    static string DescribeError(string? code, string? desc, string body, HttpResponseMessage res) =>
        MisaErrorText(code) ?? FirstNonEmpty(desc, code, $"HTTP {(int)res.StatusCode}: {Trim(body)}");

    /// <summary>Mã lỗi hay gặp của meInvoice → tiếng Việt dễ hiểu.</summary>
    static string? MisaErrorText(string? code) => (code ?? "").Trim() switch
    {
        "InvalidAppID" => "AppID MISA không đúng — liên hệ MISA để lấy AppID tích hợp",
        "InactiveAppID" => "AppID MISA đã bị ngừng — liên hệ MISA",
        "UnAuthorize" => "Sai tài khoản / mật khẩu / MST MISA meInvoice",
        "InvalidTaxCode" => "MST người bán không khớp tài khoản MISA",
        "InvoiceDuplicated" => "Hóa đơn đã tồn tại trên MISA (trùng RefID) — dùng Đồng bộ",
        "InvoiceNumberNotContinuous" => "Số hóa đơn MISA không liên tục",
        "InvalidInvoiceSeries" or "InvSeriesNotExist" => "Ký hiệu hóa đơn không tồn tại trên MISA",
        "SignatureEmpty" or "InvalidSignature" => "Chưa cấu hình chữ ký số HSM trên MISA",
        "InvalidXMLData" => "Dữ liệu hóa đơn không hợp lệ theo chuẩn CQT",
        _ => null,
    };

    static List<JsonElement> ReadJsonArray(JsonElement root, string name)
    {
        var list = new List<JsonElement>();
        if (!TryGetCI(root, name, out var el)) return list;
        if (el.ValueKind == JsonValueKind.String)
        {
            // MISA trả mảng dưới dạng chuỗi JSON.
            var s = el.GetString();
            if (string.IsNullOrWhiteSpace(s) || !s.TrimStart().StartsWith('[')) return list;
            using var inner = JsonDocument.Parse(s);
            list.AddRange(inner.RootElement.EnumerateArray().Select(x => x.Clone()));
            return list;
        }
        if (el.ValueKind == JsonValueKind.Array)
            list.AddRange(el.EnumerateArray().Select(x => x.Clone()));
        return list;
    }

    static bool TryGetCI(JsonElement root, string name, out JsonElement value)
    {
        value = default;
        if (root.ValueKind != JsonValueKind.Object) return false;
        foreach (var p in root.EnumerateObject())
        {
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                value = p.Value;
                return true;
            }
        }
        return false;
    }

    static string? ReadStr(JsonElement el, string name)
    {
        if (!TryGetCI(el, name, out var p)) return null;
        var s = p.ValueKind switch
        {
            JsonValueKind.String => p.GetString(),
            JsonValueKind.Null or JsonValueKind.Undefined => null,
            _ => p.ToString(),
        };
        return string.IsNullOrWhiteSpace(s) ? null : s.Trim();
    }

    static int ReadInt(JsonElement el, string name)
    {
        if (!TryGetCI(el, name, out var p)) return 0;
        if (p.ValueKind == JsonValueKind.Number && p.TryGetInt32(out var n)) return n;
        return int.TryParse(p.ToString(), out n) ? n : 0;
    }

    static bool ReadBool(JsonElement el, string name)
    {
        if (!TryGetCI(el, name, out var p)) return false;
        return p.ValueKind == JsonValueKind.True ||
               (p.ValueKind == JsonValueKind.String && bool.TryParse(p.GetString(), out var b) && b) ||
               (p.ValueKind == JsonValueKind.Number && p.TryGetInt32(out var n) && n != 0);
    }

    static string Lower(bool v) => v ? "true" : "false";

    static string FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v))?.Trim() ?? "";

    static string Trim(string? s)
    {
        s = (s ?? "").Replace('\n', ' ').Trim();
        return s.Length <= 500 ? s : s[..500];
    }
}
