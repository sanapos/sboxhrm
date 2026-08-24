using System.Text;
using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

public class ViettelPostShippingClient(
    IHttpClientFactory httpClientFactory,
    ILogger<ViettelPostShippingClient> logger) : IShippingCarrierClient
{
    public string CarrierCode => ShippingCarrierCodes.ViettelPost;

    string BaseUrl(PosShippingCarrierSetting s)
    {
        if (!string.IsNullOrWhiteSpace(s.ApiBaseUrl)) return s.ApiBaseUrl.Trim().TrimEnd('/');
        return s.UseSandbox
            ? "https://partnerdev.viettelpost.vn/v2"
            : "https://partner.viettelpost.vn/v2";
    }

    static bool LooksLikePartnerJwt(string? token)
    {
        var t = (token ?? "").Trim();
        return t.Length >= 40 && t.Contains('.');
    }

    static string? ParseTokenFromLogin(JsonElement root)
    {
        if (root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Object)
        {
            if (data.TryGetProperty("token", out var tk) && tk.ValueKind == JsonValueKind.String)
                return tk.GetString();
            if (data.TryGetProperty("Token", out var tk2) && tk2.ValueKind == JsonValueKind.String)
                return tk2.GetString();
        }
        return null;
    }

    static string? ParseApiError(JsonElement root, string? raw = null)
    {
        if (root.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String)
        {
            var s = m.GetString();
            if (!string.IsNullOrWhiteSpace(s)) return s;
        }
        if (root.TryGetProperty("Message", out var m2) && m2.ValueKind == JsonValueKind.String)
        {
            var s = m2.GetString();
            if (!string.IsNullOrWhiteSpace(s)) return s;
        }
        return string.IsNullOrWhiteSpace(raw) ? "Viettel Post từ chối yêu cầu" : raw;
    }

    static bool IsApiError(JsonElement root)
    {
        if (root.TryGetProperty("error", out var er) &&
            (er.ValueKind == JsonValueKind.True ||
             (er.ValueKind == JsonValueKind.String && er.GetString()?.Equals("true", StringComparison.OrdinalIgnoreCase) == true)))
            return true;
        if (root.TryGetProperty("status", out var st) && st.ValueKind == JsonValueKind.Number)
        {
            var code = st.GetInt32();
            if (code is not 0 and not 200) return true;
        }
        return false;
    }

    static bool IsPartnerPortalToken(string? token)
    {
        var t = (token ?? "").Trim();
        return t.Length > 0 && t.Length <= 36 && !t.Contains('.');
    }

    static string MapTokenError(string? msg, bool forCreate)
    {
        if (string.IsNullOrWhiteSpace(msg)) return msg ?? "";
        if (msg.Contains("Token invalid", StringComparison.OrdinalIgnoreCase) && forCreate)
            return "Token không hợp lệ để tạo vận đơn. Dán token bí mật 32 ký tự từ viettelpost.vn rồi Lưu (hệ thống đổi sang JWT), "
                   + "hoặc nhập đúng Mật khẩu Viettel Post, hoặc dán JWT (eyJ...).";
        if (msg.Contains("Username or password", StringComparison.OrdinalIgnoreCase))
            return "Sai Username/Mật khẩu Viettel Post — cập nhật mật khẩu đúng rồi bấm Lưu.";
        return msg;
    }

    /// <summary>Login + ownerconnect → JWT dùng cho tạo vận đơn.</summary>
    public async Task<(string? Token, string? Error)> TryLoginSessionTokenAsync(
        PosShippingCarrierSetting settings, CancellationToken ct = default)
    {
        var user = (settings.Username ?? "").Trim();
        var pass = (settings.Password ?? "").Trim();
        if (user.Length == 0 || pass.Length == 0)
            return (null, "Thiếu Username/Mật khẩu Viettel Post");

        var http = httpClientFactory.CreateClient("shipping-viettelpost");
        var baseUrl = BaseUrl(settings);
        var loginBody = JsonSerializer.Serialize(new Dictionary<string, string>
        {
            ["USERNAME"] = user,
            ["PASSWORD"] = pass,
        });

        using var loginReq = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/user/login")
        {
            Content = new StringContent(loginBody, Encoding.UTF8, "application/json"),
        };
        using var loginRes = await http.SendAsync(loginReq, ct);
        var loginRaw = await loginRes.Content.ReadAsStringAsync(ct);
        using var loginDoc = JsonDocument.Parse(loginRaw);
        var loginRoot = loginDoc.RootElement;
        if (IsApiError(loginRoot))
            return (null, MapTokenError(ParseApiError(loginRoot, loginRaw), forCreate: true));

        var temp = ParseTokenFromLogin(loginRoot);
        if (string.IsNullOrWhiteSpace(temp))
            return (null, "Viettel Post không trả token sau đăng nhập");

        try
        {
            var (longToken, _) = await TryOwnerConnectAsync(settings, temp, ct);
            if (!string.IsNullOrWhiteSpace(longToken))
                return (longToken, null);
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "ViettelPost ownerconnect skipped");
        }

        return (temp, null);
    }

    /// <summary>Đổi token bí mật viettelpost.vn (32 ký tự) → JWT qua API LoginVTP.</summary>
    public async Task<(string? Token, string? Error)> TryLoginVtpTokenAsync(
        PosShippingCarrierSetting settings, string? secretToken = null, CancellationToken ct = default)
    {
        var secret = (secretToken ?? settings.ApiToken ?? "").Trim();
        if (!IsPartnerPortalToken(secret))
            return (null, "Không phải token bí mật Viettel Post (32 ký tự từ viettelpost.vn)");

        var http = httpClientFactory.CreateClient("shipping-viettelpost");
        var baseUrl = BaseUrl(settings);
        var body = JsonSerializer.Serialize(new Dictionary<string, string> { ["token"] = secret });

        foreach (var path in new[] { "/user/LoginVTP", "/user/loginvtp" })
        {
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}{path}")
                {
                    Content = new StringContent(body, Encoding.UTF8, "application/json"),
                };
                using var res = await http.SendAsync(req, ct);
                var raw = await res.Content.ReadAsStringAsync(ct);
                using var doc = JsonDocument.Parse(raw);
                var root = doc.RootElement;
                if (IsApiError(root))
                {
                    var err = ParseApiError(root, raw);
                    logger.LogWarning("ViettelPost LoginVTP {Path}: {Msg}", path, err);
                    continue;
                }

                var jwt = ParseTokenFromLogin(root);
                if (string.IsNullOrWhiteSpace(jwt))
                    continue;

                // Token dài hạn nếu có Username/Password.
                if (!string.IsNullOrWhiteSpace(settings.Username)
                    && !string.IsNullOrWhiteSpace(settings.Password))
                {
                    var (longJwt, _) = await TryOwnerConnectAsync(settings, jwt, ct);
                    if (!string.IsNullOrWhiteSpace(longJwt))
                        return (longJwt, null);
                }

                return (jwt, null);
            }
            catch (Exception ex)
            {
                logger.LogDebug(ex, "ViettelPost LoginVTP {Path} failed", path);
            }
        }

        return (null, "LoginVTP thất bại — token bí mật không hợp lệ hoặc đã hết hạn. "
                      + "Tạo lại token tại viettelpost.vn/cau-hinh-tai-khoan.");
    }

    async Task<(string? Token, string? Error)> TryOwnerConnectAsync(
        PosShippingCarrierSetting settings, string shortToken, CancellationToken ct)
    {
        var user = (settings.Username ?? "").Trim();
        var pass = (settings.Password ?? "").Trim();
        if (user.Length == 0 || pass.Length == 0)
            return (null, null);

        var http = httpClientFactory.CreateClient("shipping-viettelpost");
        var baseUrl = BaseUrl(settings);
        var loginBody = JsonSerializer.Serialize(new Dictionary<string, string>
        {
            ["USERNAME"] = user,
            ["PASSWORD"] = pass,
        });

        using var connReq = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/user/ownerconnect")
        {
            Content = new StringContent(loginBody, Encoding.UTF8, "application/json"),
        };
        connReq.Headers.TryAddWithoutValidation("Token", shortToken);
        using var connRes = await http.SendAsync(connReq, ct);
        var connRaw = await connRes.Content.ReadAsStringAsync(ct);
        using var connDoc = JsonDocument.Parse(connRaw);
        var connRoot = connDoc.RootElement;
        if (IsApiError(connRoot))
        {
            var ocErr = ParseApiError(connRoot, connRaw);
            logger.LogWarning("ViettelPost ownerconnect: {Msg}", ocErr);
            return (null, ocErr);
        }

        var longToken = ParseTokenFromLogin(connRoot);
        return string.IsNullOrWhiteSpace(longToken) ? (null, null) : (longToken, null);
    }

    async Task<string?> LoginAsync(PosShippingCarrierSetting settings, CancellationToken ct)
    {
        var (token, _) = await TryLoginSessionTokenAsync(settings, ct);
        return token;
    }

    async Task<string?> EnsureQuoteTokenAsync(PosShippingCarrierSetting settings, CancellationToken ct)
    {
        if (LooksLikePartnerJwt(settings.ApiToken))
            return settings.ApiToken!.Trim();
        if (!string.IsNullOrWhiteSpace(settings.ApiToken))
            return settings.ApiToken.Trim();
        return await LoginAsync(settings, ct);
    }

    async Task<(string? Token, string? Error)> EnsureCreateTokenAsync(
        PosShippingCarrierSetting settings, CancellationToken ct)
    {
        if (LooksLikePartnerJwt(settings.ApiToken))
            return (settings.ApiToken!.Trim(), null);

        if (IsPartnerPortalToken(settings.ApiToken))
        {
            var (fromVtp, vtpErr) = await TryLoginVtpTokenAsync(settings, ct: ct);
            if (!string.IsNullOrWhiteSpace(fromVtp))
                return (fromVtp, null);
            if (!string.IsNullOrWhiteSpace(vtpErr))
                return (null, vtpErr);
        }

        var (fromLogin, loginErr) = await TryLoginSessionTokenAsync(settings, ct);
        if (!string.IsNullOrWhiteSpace(fromLogin))
            return (fromLogin, null);

        if (!string.IsNullOrWhiteSpace(loginErr))
            return (null, loginErr);

        return (null, "Nhập token bí mật viettelpost.vn, Username + Mật khẩu, hoặc JWT (eyJ...) để tạo vận đơn.");
    }

    async Task<string?> EnsureTokenAsync(PosShippingCarrierSetting settings, CancellationToken ct) =>
        await EnsureQuoteTokenAsync(settings, ct);

    static string PrintPortalBaseUrl(bool sandbox) =>
        sandbox
            ? "https://devdigitalize.viettelpost.vn/DigitalizePrint/report.do"
            : "https://digitalize.viettelpost.vn/DigitalizePrint/report.do";

    static string BuildPrintLabelUrl(bool sandbox, string printCode, int labelType = 1) =>
        $"{PrintPortalBaseUrl(sandbox)}?type={labelType}&bill={Uri.EscapeDataString(printCode)}&showPostage=1";

    async Task<(JsonElement Root, string Raw, string? Error)> PostJsonAsync(
        PosShippingCarrierSetting settings, string path, object body, string token,
        CancellationToken ct)
    {
        var http = httpClientFactory.CreateClient("shipping-viettelpost");
        using var reqMsg = new HttpRequestMessage(HttpMethod.Post, $"{BaseUrl(settings)}{path}")
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"),
        };
        reqMsg.Headers.TryAddWithoutValidation("Token", token);
        using var res = await http.SendAsync(reqMsg, ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
        var root = doc.RootElement.Clone();
        if (IsApiError(root))
            return (default, raw, ParseApiError(root, raw));
        return (root, raw, null);
    }

    async Task<(JsonElement Root, string Raw, string? Error)> GetJsonAsync(
        PosShippingCarrierSetting settings, string path, string token, CancellationToken ct)
    {
        var http = httpClientFactory.CreateClient("shipping-viettelpost");
        using var reqMsg = new HttpRequestMessage(HttpMethod.Get, $"{BaseUrl(settings)}{path}");
        reqMsg.Headers.TryAddWithoutValidation("Token", token);
        using var res = await http.SendAsync(reqMsg, ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
        var root = doc.RootElement.Clone();
        if (IsApiError(root))
            return (default, raw, ParseApiError(root, raw));
        return (root, raw, null);
    }

    static List<ShippingAddressItem> ParseAddressList(JsonElement root, string idKey, string nameKey)
    {
        JsonElement list = default;
        if (root.ValueKind == JsonValueKind.Array) list = root;
        else if (root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
            list = data;
        else if (root.TryGetProperty("DATA", out var data2) && data2.ValueKind == JsonValueKind.Array)
            list = data2;

        if (list.ValueKind != JsonValueKind.Array) return [];

        var items = new List<ShippingAddressItem>();
        foreach (var el in list.EnumerateArray())
        {
            string? id = null;
            if (el.TryGetProperty(idKey, out var idProp))
                id = idProp.ValueKind == JsonValueKind.Number
                    ? idProp.GetRawText()
                    : idProp.GetString();
            if (string.IsNullOrWhiteSpace(id)) continue;

            var name = el.TryGetProperty(nameKey, out var n) ? n.GetString() : null;
            if (string.IsNullOrWhiteSpace(name)) continue;

            string? code = el.TryGetProperty("PROVINCE_CODE", out var pc) ? pc.GetString() : null;
            string? parent = null;
            if (el.TryGetProperty("PROVINCE_ID", out var pid))
                parent = pid.ValueKind == JsonValueKind.Number ? pid.GetRawText() : pid.GetString();
            else if (el.TryGetProperty("DISTRICT_ID", out var did))
                parent = did.ValueKind == JsonValueKind.Number ? did.GetRawText() : did.GetString();

            items.Add(new ShippingAddressItem(id.Trim(), name.Trim(), code, parent));
        }
        return items;
    }

    public async Task<IReadOnlyList<ShippingAddressItem>> ListProvincesAsync(
        PosShippingCarrierSetting settings, CancellationToken ct = default)
    {
        var token = await EnsureTokenAsync(settings, ct);
        if (string.IsNullOrWhiteSpace(token)) return [];
        var (_, raw, err) = await GetJsonAsync(
            settings, "/categories/listProvinceById?provinceId=-1", token, ct);
        if (err != null) return [];
        using var doc = JsonDocument.Parse(raw);
        return ParseAddressList(doc.RootElement, "PROVINCE_ID", "PROVINCE_NAME");
    }

    public async Task<IReadOnlyList<ShippingAddressItem>> ListDistrictsAsync(
        PosShippingCarrierSetting settings, int provinceId, CancellationToken ct = default)
    {
        var token = await EnsureTokenAsync(settings, ct);
        if (string.IsNullOrWhiteSpace(token)) return [];
        var (_, raw, err) = await GetJsonAsync(
            settings, $"/categories/listDistrict?provinceId={provinceId}", token, ct);
        if (err != null) return [];
        using var doc = JsonDocument.Parse(raw);
        return ParseAddressList(doc.RootElement, "DISTRICT_ID", "DISTRICT_NAME");
    }

    public async Task<IReadOnlyList<ShippingAddressItem>> ListWardsAsync(
        PosShippingCarrierSetting settings, int districtId, CancellationToken ct = default)
    {
        var token = await EnsureTokenAsync(settings, ct);
        if (string.IsNullOrWhiteSpace(token)) return [];
        var (_, raw, err) = await GetJsonAsync(
            settings, $"/categories/listWards?districtId={districtId}", token, ct);
        if (err != null) return [];
        using var doc = JsonDocument.Parse(raw);
        return ParseAddressList(doc.RootElement, "WARDS_ID", "WARDS_NAME");
    }

    public async Task<ShippingLabelResult> GetPrintLabelAsync(
        PosShippingCarrierSetting settings, string trackingCode, CancellationToken ct = default)
    {
        var (token, tokenErr) = await EnsureCreateTokenAsync(settings, ct);
        if (string.IsNullOrWhiteSpace(token))
            return new(false, CarrierCode, Message: tokenErr ?? "Thiếu token Viettel Post");

        var tracking = trackingCode.Trim();
        if (tracking.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã vận đơn");

        var expiry = DateTimeOffset.UtcNow.AddDays(7).ToUnixTimeMilliseconds();
        var body = new Dictionary<string, object?>
        {
            ["EXPIRY_TIME"] = expiry,
            ["ORDER_ARRAY"] = new[] { tracking },
        };

        string? printCode = null;
        foreach (var path in new[] { "/order/encryptLinkPrint", "/order/printOrder" })
        {
            try
            {
                var (root, _, err) = await PostJsonAsync(settings, path, body, token, ct);
                if (err != null) continue;
                if (root.TryGetProperty("message", out var msg) && msg.ValueKind == JsonValueKind.String)
                {
                    var s = msg.GetString()?.Trim();
                    if (!string.IsNullOrWhiteSpace(s) && !s.Equals("OK", StringComparison.OrdinalIgnoreCase))
                        printCode = s;
                }
                if (string.IsNullOrWhiteSpace(printCode)
                    && root.TryGetProperty("Message", out var msg2)
                    && msg2.ValueKind == JsonValueKind.String)
                {
                    var s = msg2.GetString()?.Trim();
                    if (!string.IsNullOrWhiteSpace(s) && !s.Equals("OK", StringComparison.OrdinalIgnoreCase))
                        printCode = s;
                }
                if (!string.IsNullOrWhiteSpace(printCode)) break;
            }
            catch (Exception ex)
            {
                logger.LogDebug(ex, "ViettelPost print {Path} failed", path);
            }
        }

        if (string.IsNullOrWhiteSpace(printCode))
            return new(false, CarrierCode, Message: "Không lấy được mã in vận đơn Viettel Post");

        var url = BuildPrintLabelUrl(settings.UseSandbox, printCode);
        return new(true, CarrierCode, LabelUrl: url, PrintCode: printCode,
            Message: "Đã lấy link in vận đơn");
    }

    public async Task<ShippingCancelResult> UpdateOrderStatusAsync(
        PosShippingCarrierSetting settings, string trackingCode, int type, string? note,
        CancellationToken ct = default)
    {
        var (token, tokenErr) = await EnsureCreateTokenAsync(settings, ct);
        if (string.IsNullOrWhiteSpace(token))
            return new(false, CarrierCode, Message: tokenErr ?? "Thiếu token Viettel Post");

        var tracking = trackingCode.Trim();
        if (tracking.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã vận đơn");

        var body = new Dictionary<string, object?>
        {
            ["TYPE"] = type,
            ["ORDER_NUMBER"] = tracking,
            ["NOTE"] = (note ?? "").Trim().Length > 0 ? note!.Trim()[..Math.Min(note.Trim().Length, 150)] : "Hủy qua SBOX POS",
        };

        try
        {
            var (_, _, err) = await PostJsonAsync(settings, "/order/UpdateOrder", body, token, ct);
            if (err != null)
                return new(false, CarrierCode, Message: err);
            return new(true, CarrierCode, Message: type == 4 ? "Đã yêu cầu hủy vận đơn" : "Đã cập nhật trạng thái");
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "ViettelPost UpdateOrder failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    static int? ReadStatusCode(JsonElement el)
    {
        foreach (var key in new[] { "ORDER_STATUS", "orderStatus", "STATUS", "status" })
        {
            if (!el.TryGetProperty(key, out var p)) continue;
            if (p.ValueKind == JsonValueKind.Number && p.TryGetInt32(out var n)) return n;
            if (p.ValueKind == JsonValueKind.String && int.TryParse(p.GetString(), out var ns)) return ns;
        }
        return null;
    }

    static string? ReadStatusName(JsonElement el)
    {
        foreach (var key in new[] { "STATUS_NAME", "statusName", "STATUS_NAME_VN", "status_name" })
        {
            if (el.TryGetProperty(key, out var p) && p.ValueKind == JsonValueKind.String)
            {
                var s = p.GetString();
                if (!string.IsNullOrWhiteSpace(s)) return s.Trim();
            }
        }
        return null;
    }

    static List<ShippingTrackingEvent> ParseTrackingEvents(JsonElement root)
    {
        JsonElement list = default;
        if (root.ValueKind == JsonValueKind.Array) list = root;
        else
        {
            foreach (var key in new[] { "TRACKING", "tracking", "HISTORY", "history", "data", "DATA" })
            {
                if (!root.TryGetProperty(key, out var nested)) continue;
                if (nested.ValueKind == JsonValueKind.Array)
                {
                    list = nested;
                    break;
                }
            }
        }

        if (list.ValueKind != JsonValueKind.Array) return [];

        var events = new List<ShippingTrackingEvent>();
        foreach (var el in list.EnumerateArray())
        {
            events.Add(new ShippingTrackingEvent(
                ReadStatusCode(el),
                ReadStatusName(el),
                el.TryGetProperty("ORDER_STATUSDATE", out var dt) ? dt.GetString()
                    : el.TryGetProperty("statusDate", out var dt2) ? dt2.GetString() : null,
                el.TryGetProperty("LOCALION_CURRENTLY", out var loc) ? loc.GetString()
                    : el.TryGetProperty("location", out var loc2) ? loc2.GetString() : null,
                el.TryGetProperty("NOTE", out var note) ? note.GetString()
                    : el.TryGetProperty("note", out var note2) ? note2.GetString() : null));
        }
        return events;
    }

    public async Task<ShippingTrackingResult> GetTrackingAsync(
        PosShippingCarrierSetting settings, string trackingCode, CancellationToken ct = default)
    {
        var (token, tokenErr) = await EnsureCreateTokenAsync(settings, ct);
        if (string.IsNullOrWhiteSpace(token))
            return new(false, CarrierCode, Message: tokenErr ?? "Thiếu token Viettel Post");

        var tracking = trackingCode.Trim();
        if (tracking.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã vận đơn");

        var body = new Dictionary<string, string> { ["ORDER_NUMBER"] = tracking };
        string? raw = null;
        JsonElement root = default;
        string? lastErr = null;

        foreach (var path in new[]
                 {
                     "/order/getOrderInfo",
                     "/order/listOrderTracking",
                     "/order/OrderTracking",
                 })
        {
            try
            {
                var (r, rRaw, err) = await PostJsonAsync(settings, path, body, token, ct);
                if (err != null)
                {
                    lastErr = err;
                    continue;
                }
                root = r;
                raw = rRaw;
                break;
            }
            catch (Exception ex)
            {
                lastErr = ex.Message;
                logger.LogDebug(ex, "ViettelPost tracking {Path} failed", path);
            }
        }

        if (raw == null)
            return new(false, CarrierCode, Message: lastErr ?? "Không tra được hành trình");

        JsonElement data = root;
        if (root.TryGetProperty("data", out var d) && d.ValueKind == JsonValueKind.Object)
            data = d;
        else if (root.TryGetProperty("DATA", out var d2) && d2.ValueKind == JsonValueKind.Object)
            data = d2;

        var statusCode = ReadStatusCode(data);
        if (statusCode == null) statusCode = ReadStatusCode(root);
        var statusName = ReadStatusName(data) ?? ReadStatusName(root);
        var events = ParseTrackingEvents(root);
        if (events.Count == 0) events = ParseTrackingEvents(data);

        var mapped = ViettelPostWebhookHelper.MapOnlineStatus(statusCode);
        return new(true, CarrierCode, statusCode, statusName, mapped, events, RawJson: raw);
    }

    /// <summary>
    /// NLP Viettel cần địa chỉ đủ tỉnh/quận/phường — chỉ số nhà sẽ trả
    /// "Price does not apply to this itinerary!".
    /// </summary>
    static string BuildFullAddress(
        string? street, string? ward, string? district, string? province)
    {
        var parts = new List<string>();
        void Add(string? x)
        {
            x = (x ?? "").Trim();
            if (x.Length == 0) return;
            if (parts.Any(p => p.Contains(x, StringComparison.OrdinalIgnoreCase)
                               || x.Contains(p, StringComparison.OrdinalIgnoreCase)))
                return;
            parts.Add(x);
        }
        Add(street);
        Add(ward);
        Add(district);
        Add(province);
        return string.Join(", ", parts);
    }

    static string BuildSenderAddress(PosShippingCarrierSetting s) =>
        BuildFullAddress(s.PickupAddress, s.FromWardName, s.FromDistrictName, s.FromProvinceName);

    static string BuildReceiverAddress(ShippingQuoteRequest request) =>
        BuildFullAddress(request.ToAddress, request.ToWard, request.ToDistrict, request.ToProvince);

    static JsonElement ResolveServiceList(JsonElement root)
    {
        if (root.TryGetProperty("RESULT", out var result) &&
            result.ValueKind == JsonValueKind.Array)
            return result;
        if (root.TryGetProperty("result", out var result2) &&
            result2.ValueKind == JsonValueKind.Array)
            return result2;
        if (root.TryGetProperty("data", out var data))
        {
            if (data.ValueKind == JsonValueKind.Array) return data;
            if (data.ValueKind == JsonValueKind.Object &&
                data.TryGetProperty("RESULT", out var nested) &&
                nested.ValueKind == JsonValueKind.Array)
                return nested;
        }
        if (root.ValueKind == JsonValueKind.Array) return root;
        return default;
    }

    public async Task<ShippingQuoteResult> QuoteAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, CancellationToken ct = default)
    {
        var token = await EnsureTokenAsync(settings, ct);
        if (string.IsNullOrWhiteSpace(token))
            return new(false, CarrierCode, 0,
                Message: "Thiếu Token Partner hoặc Username/Password Viettel Post không hợp lệ");

        var senderAddr = BuildSenderAddress(settings);
        var receiverAddr = BuildReceiverAddress(request);
        if (string.IsNullOrWhiteSpace(senderAddr) || string.IsNullOrWhiteSpace(receiverAddr))
            return new(false, CarrierCode, 0, Message: "Thiếu địa chỉ gửi/nhận (số nhà + phường + tỉnh)");

        var body = new Dictionary<string, object?>
        {
            ["SENDER_ADDRESS"] = senderAddr,
            ["RECEIVER_ADDRESS"] = receiverAddr,
            ["PRODUCT_TYPE"] = "HH",
            ["PRODUCT_WEIGHT"] = Math.Max(100, request.WeightGrams),
            ["PRODUCT_PRICE"] = (int)Math.Max(0, request.InsuranceValue),
            ["MONEY_COLLECTION"] = (int)Math.Max(0, request.CodAmount),
            ["TYPE"] = 1,
        };

        try
        {
            var http = httpClientFactory.CreateClient("shipping-viettelpost");
            var url = $"{BaseUrl(settings)}/order/getPriceAllNlp";
            using var reqMsg = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"),
            };
            reqMsg.Headers.TryAddWithoutValidation("Token", token);
            using var res = await http.SendAsync(reqMsg, ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;

            if (IsApiError(root))
                return new(false, CarrierCode, 0, Message: ParseApiError(root, raw), RawJson: raw);

            var list = ResolveServiceList(root);
            if (list.ValueKind != JsonValueKind.Array || list.GetArrayLength() == 0)
            {
                var msg = ParseApiError(root, raw);
                if (msg?.Contains("itinerary", StringComparison.OrdinalIgnoreCase) == true)
                    msg = "Địa chỉ gửi/nhận chưa đủ chi tiết (số nhà, phường, tỉnh) — kiểm tra lại điểm lấy hàng";
                return new(false, CarrierCode, 0, Message: msg ?? "Không có bảng giá", RawJson: raw);
            }

            var first = list[0];
            var fee = 0m;
            if (first.TryGetProperty("GIA_CUOC", out var gc)) fee = gc.GetDecimal();
            else if (first.TryGetProperty("price", out var p)) fee = p.GetDecimal();
            else if (first.TryGetProperty("MONEY_TOTAL", out var mt)) fee = mt.GetDecimal();
            var svc = first.TryGetProperty("TEN_DICHVU", out var tn) ? tn.GetString()
                : first.TryGetProperty("SERVICE_NAME", out var sn) ? sn.GetString() : "Viettel Post";
            var svcCode = first.TryGetProperty("MA_DV_CHINH", out var md) ? md.GetString()
                : first.TryGetProperty("SERVICE_CODE", out var sc) ? sc.GetString() : null;
            return new(true, CarrierCode, fee, ServiceName: svc, ServiceCode: svcCode, RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "ViettelPost quote failed");
            return new(false, CarrierCode, 0, Message: ex.Message);
        }
    }

    public async Task<ShippingCreateResult> CreateAsync(
        PosShippingCarrierSetting settings, PosSaleOrder order, ShippingCreateRequest request,
        CancellationToken ct = default)
    {
        var (token, tokenErr) = await EnsureCreateTokenAsync(settings, ct);
        if (string.IsNullOrWhiteSpace(token))
            return new(false, CarrierCode, Message: tokenErr ?? "Không lấy được token tạo vận đơn");

        var senderAddr = BuildSenderAddress(settings);
        var receiverAddr = BuildFullAddress(
            order.DeliveryAddress, order.DeliveryWard, order.DeliveryDistrict, order.DeliveryProvince);

        var merchantRef = $"{order.OrderNo}-{order.Id:N}";
        if (merchantRef.Length > 50) merchantRef = merchantRef[..50];

        var body = new Dictionary<string, object?>
        {
            ["ORDER_NUMBER"] = merchantRef,
            ["SENDER_FULLNAME"] = settings.PickupName ?? "Cửa hàng",
            ["SENDER_ADDRESS"] = senderAddr,
            ["SENDER_PHONE"] = settings.PickupPhone ?? "",
            ["RECEIVER_FULLNAME"] = order.CustomerName ?? "Khách",
            ["RECEIVER_ADDRESS"] = string.IsNullOrWhiteSpace(receiverAddr)
                ? (order.DeliveryAddress ?? "")
                : receiverAddr,
            ["RECEIVER_PHONE"] = order.DeliveryPhone ?? "",
            ["PRODUCT_NAME"] = $"Đơn {order.OrderNo}",
            ["PRODUCT_DESCRIPTION"] = request.Note ?? order.Note ?? "",
            ["PRODUCT_QUANTITY"] = 1,
            ["PRODUCT_PRICE"] = (int)Math.Max(0, order.PayableTotal),
            ["PRODUCT_WEIGHT"] = Math.Max(100, request.WeightGrams),
            ["PRODUCT_TYPE"] = "HH",
            ["ORDER_PAYMENT"] = ResolveOrderPayment(request),
            ["MONEY_COLLECTION"] = (int)Math.Max(0, request.CodAmount ?? 0),
            ["ORDER_SERVICE"] = string.IsNullOrWhiteSpace(request.ServiceCode) ? "VCN" : request.ServiceCode,
            ["ORDER_SERVICE_ADD"] = "",
            ["ORDER_NOTE"] = request.Note ?? "",
            ["CHECK_UNIQUE"] = true,
        };

        static int ResolveOrderPayment(ShippingCreateRequest req)
        {
            var cod = Math.Max(0, req.CodAmount ?? 0);
            var shopPays = ShippingFeePayer.ShopPaysCarrier(req.ShipFeePayer);
            // 1 không thu · 2 thu hàng+cước (khách trả ship) · 3 thu hàng, shop trả cước
            if (cod <= 0) return 1;
            return shopPays ? 3 : 2;
        }

        static string? ReadTracking(JsonElement el)
        {
            foreach (var key in new[]
                     {
                         "ORDER_NUMBER", "orderNumber", "BILL_CODE", "billCode",
                         "MA_VANDON", "MA_PHIEU_GUI", "TRACKING_CODE", "trackingCode"
                     })
            {
                if (!el.TryGetProperty(key, out var p)) continue;
                if (p.ValueKind == JsonValueKind.String)
                {
                    var s = p.GetString();
                    if (!string.IsNullOrWhiteSpace(s)) return s.Trim();
                }
                else if (p.ValueKind == JsonValueKind.Number)
                {
                    return p.GetRawText();
                }
            }
            return null;
        }

        try
        {
            var http = httpClientFactory.CreateClient("shipping-viettelpost");
            var url = $"{BaseUrl(settings)}/order/createOrderNlp";
            using var reqMsg = new HttpRequestMessage(HttpMethod.Post, url)
            {
                Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"),
            };
            reqMsg.Headers.TryAddWithoutValidation("Token", token);
            using var res = await http.SendAsync(reqMsg, ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            if (IsApiError(root))
                return new(false, CarrierCode,
                    Message: MapTokenError(ParseApiError(root, raw), forCreate: true), RawJson: raw);

            string? tracking = ReadTracking(root);
            decimal? fee = null;
            if (root.TryGetProperty("data", out var data))
            {
                tracking ??= ReadTracking(data);
                if (data.TryGetProperty("MONEY_TOTAL", out var mt)) fee = mt.GetDecimal();
            }
            if (string.IsNullOrWhiteSpace(tracking))
                return new(false, CarrierCode,
                    Message: ParseApiError(root, raw) ?? "Không lấy được mã vận đơn Viettel Post",
                    RawJson: raw);

            string? labelUrl = null;
            try
            {
                var label = await GetPrintLabelAsync(settings, tracking, ct);
                if (label.Success) labelUrl = label.LabelUrl;
            }
            catch (Exception ex)
            {
                logger.LogDebug(ex, "ViettelPost auto label after create skipped");
            }

            return new(true, CarrierCode, TrackingCode: tracking, CarrierOrderId: tracking,
                LabelUrl: labelUrl, Fee: fee,
                Message: $"Tạo vận đơn thành công · Mã {tracking}", RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "ViettelPost create failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }
}
