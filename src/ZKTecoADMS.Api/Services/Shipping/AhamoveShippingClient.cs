using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>
/// AhaMove Partner API v3: API Key + SĐT → JWT (Bearer), rồi POST estimates / orders.
/// Docs: https://developers.ahamove.com
/// Staging: https://partner-apistg.ahamove.com — Production: https://partner-api.ahamove.com
/// </summary>
public class AhamoveShippingClient(IHttpClientFactory httpClientFactory, ILogger<AhamoveShippingClient> logger)
    : IShippingCarrierClient
{
    public string CarrierCode => ShippingCarrierCodes.Ahamove;

    static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    string BaseUrl(PosShippingCarrierSetting s)
    {
        if (!string.IsNullOrWhiteSpace(s.ApiBaseUrl)) return s.ApiBaseUrl.Trim().TrimEnd('/');
        return s.UseSandbox
            ? "https://partner-apistg.ahamove.com"
            : "https://partner-api.ahamove.com";
    }

    /// <summary>ExtraJson: lat/lng điểm lấy, service_id (SGN-BIKE) hoặc group (BIKE).</summary>
    static Dictionary<string, JsonElement>? ParseExtra(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.EnumerateObject()
                .ToDictionary(p => p.Name, p => p.Value.Clone());
        }
        catch { return null; }
    }

    static string? ExtraString(Dictionary<string, JsonElement>? extra, string key)
    {
        if (extra == null || !extra.TryGetValue(key, out var el)) return null;
        return el.ValueKind == JsonValueKind.String ? el.GetString() : el.ToString();
    }

    static double? ExtraDouble(Dictionary<string, JsonElement>? extra, string key)
    {
        if (extra == null || !extra.TryGetValue(key, out var el)) return null;
        if (el.ValueKind == JsonValueKind.Number && el.TryGetDouble(out var d)) return d;
        if (el.ValueKind == JsonValueKind.String &&
            double.TryParse(el.GetString(), System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var p))
            return p;
        return null;
    }

    /// <summary>AhaMove mobile: 849xxxxxxxx.</summary>
    public static string? NormalizeVnMobile(string? raw)
    {
        var d = new string((raw ?? "").Where(char.IsDigit).ToArray());
        if (d.Length == 0) return null;
        if (d.StartsWith("84") && d.Length >= 11) return d;
        if (d.StartsWith("0") && d.Length >= 10) return "84" + d[1..];
        if (d.Length == 9) return "84" + d;
        return d;
    }

    static string? AccountMobile(PosShippingCarrierSetting s) =>
        NormalizeVnMobile(s.ShopId) ?? NormalizeVnMobile(s.PickupPhone);

    static bool JwtLooksValid(string? jwt)
    {
        if (string.IsNullOrWhiteSpace(jwt) || jwt.Count(c => c == '.') != 2) return false;
        try
        {
            var payload = jwt.Split('.')[1]
                .Replace('-', '+').Replace('_', '/');
            payload = (payload.Length % 4) switch
            {
                2 => payload + "==",
                3 => payload + "=",
                _ => payload,
            };
            using var doc = JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(payload)));
            if (doc.RootElement.TryGetProperty("exp", out var exp))
                return exp.GetInt64() > DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 60;
            return true;
        }
        catch
        {
            return jwt.Length > 40;
        }
    }

    static string? ReadToken(JsonElement root)
    {
        if (root.TryGetProperty("token", out var t)) return t.GetString();
        if (root.TryGetProperty("data", out var data) && data.TryGetProperty("token", out var t2))
            return t2.GetString();
        return null;
    }

    static string ReadError(JsonElement root, string fallback)
    {
        if (root.TryGetProperty("description", out var d) && d.ValueKind == JsonValueKind.String)
            return d.GetString() ?? fallback;
        if (root.TryGetProperty("title", out var t) && t.ValueKind == JsonValueKind.String)
            return t.GetString() ?? fallback;
        if (root.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String)
            return m.GetString() ?? fallback;
        return fallback;
    }

    /// <summary>
    /// Đổi API Key + SĐT → JWT user, cache vào <see cref="PosShippingCarrierSetting.Password"/>.
    /// </summary>
    public async Task<(bool Ok, string? Error)> EnsureUserTokenAsync(
        PosShippingCarrierSetting settings, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(settings.ApiToken))
            return (false, "Thiếu API Key AhaMove (dán key từ email tích hợp).");
        var mobile = AccountMobile(settings);
        if (string.IsNullOrWhiteSpace(mobile))
            return (false, "AhaMove cần SĐT tài khoản (ShopId hoặc SĐT lấy hàng, dạng 849…).");

        if (JwtLooksValid(settings.Password))
            return (true, null);

        var http = httpClientFactory.CreateClient("shipping-ahamove");
        var baseUrl = BaseUrl(settings);
        var apiKey = settings.ApiToken.Trim();

        var (token, err, existed) = await PostAccountTokenAsync(http, baseUrl, apiKey, mobile!, ct);
        if (string.IsNullOrWhiteSpace(token) && existed is false)
        {
            var name = string.IsNullOrWhiteSpace(settings.PickupName)
                ? "SBOX"
                : settings.PickupName.Trim();
            var address = ComposePickupAddress(settings);
            if (string.IsNullOrWhiteSpace(address))
                address = "Việt Nam";
            (token, err) = await PostRegisterAccountAsync(
                http, baseUrl, apiKey, mobile!, name, address, ct);
            if (string.IsNullOrWhiteSpace(token) &&
                (err ?? "").Contains("ACCOUNT_EXISTED", StringComparison.OrdinalIgnoreCase))
            {
                (token, err, _) = await PostAccountTokenAsync(http, baseUrl, apiKey, mobile!, ct);
            }
        }

        if (string.IsNullOrWhiteSpace(token))
            return (false, err ?? "Không lấy được token AhaMove.");

        settings.Password = token;
        return (true, null);
    }

    async Task<(string? Token, string? Error, bool? UserMissing)> PostAccountTokenAsync(
        HttpClient http, string baseUrl, string apiKey, string mobile, CancellationToken ct)
    {
        var body = JsonSerializer.Serialize(new { mobile, api_key = apiKey });
        using var res = await http.PostAsync($"{baseUrl}/v3/accounts/token",
            new StringContent(body, Encoding.UTF8, "application/json"), ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        try
        {
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var token = ReadToken(root);
            if (!string.IsNullOrWhiteSpace(token)) return (token, null, false);
            var title = root.TryGetProperty("title", out var t) ? t.GetString() : null;
            var missing = string.Equals(title, "USER_NOT_FOUND", StringComparison.OrdinalIgnoreCase);
            return (null, ReadError(root, raw), missing);
        }
        catch
        {
            return (null, raw, null);
        }
    }

    async Task<(string? Token, string? Error)> PostRegisterAccountAsync(
        HttpClient http, string baseUrl, string apiKey, string mobile, string name, string address,
        CancellationToken ct)
    {
        var body = JsonSerializer.Serialize(new
        {
            mobile,
            api_key = apiKey,
            name,
            address,
        });
        using var res = await http.PostAsync($"{baseUrl}/v3/accounts",
            new StringContent(body, Encoding.UTF8, "application/json"), ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        try
        {
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var token = ReadToken(root);
            if (!string.IsNullOrWhiteSpace(token)) return (token, null);
            return (null, ReadError(root, raw));
        }
        catch
        {
            return (null, raw);
        }
    }

    async Task<(double Lat, double Lng)?> GeocodeAsync(string address, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(address)) return null;
        try
        {
            var http = httpClientFactory.CreateClient("shipping-geocode");
            var url =
                "https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=vn&q=" +
                Uri.EscapeDataString(address.Trim());
            using var res = await http.GetAsync(url, ct);
            if (!res.IsSuccessStatusCode) return null;
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            if (doc.RootElement.ValueKind != JsonValueKind.Array || doc.RootElement.GetArrayLength() == 0)
                return null;
            var first = doc.RootElement[0];
            if (!first.TryGetProperty("lat", out var latEl) || !first.TryGetProperty("lon", out var lonEl))
                return null;
            if (!double.TryParse(latEl.GetString(), System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out var lat))
                return null;
            if (!double.TryParse(lonEl.GetString(), System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out var lng))
                return null;
            return (lat, lng);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Geocode failed for {Address}", address);
            return null;
        }
    }

    static string ComposePickupAddress(PosShippingCarrierSetting s)
    {
        var parts = new[]
        {
            s.PickupAddress, s.FromWardName, s.FromDistrictName, s.FromProvinceName,
        }.Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x!.Trim());
        return string.Join(", ", parts);
    }

    static string ComposeDropoffAddress(
        string? address, string? ward, string? district, string? province)
    {
        var parts = new[] { address, ward, district, province }
            .Where(x => !string.IsNullOrWhiteSpace(x)).Select(x => x!.Trim());
        return string.Join(", ", parts);
    }

    async Task<Dictionary<string, object?>> BuildPickupPathAsync(
        PosShippingCarrierSetting settings, Dictionary<string, JsonElement>? extra, CancellationToken ct)
    {
        var address = ComposePickupAddress(settings);
        var lat = ExtraDouble(extra, "lat");
        var lng = ExtraDouble(extra, "lng");
        if (lat is null or 0 || lng is null or 0)
        {
            var geo = await GeocodeAsync(address, ct);
            if (geo != null)
            {
                lat = geo.Value.Lat;
                lng = geo.Value.Lng;
            }
        }

        var mobile = AccountMobile(settings) ?? NormalizeVnMobile(settings.PickupPhone) ?? "";
        var point = new Dictionary<string, object?>
        {
            ["address"] = string.IsNullOrWhiteSpace(address) ? "Việt Nam" : address,
            ["name"] = settings.PickupName ?? "Shop",
            ["mobile"] = mobile,
        };
        if (lat is > 0 && lng is > 0)
        {
            point["lat"] = lat;
            point["lng"] = lng;
        }
        return point;
    }

    async Task<Dictionary<string, object?>> BuildDropoffPathAsync(
        Dictionary<string, JsonElement>? extra,
        string address, string name, string mobile,
        decimal cod, string? tracking, CancellationToken ct)
    {
        var lat = ExtraDouble(extra, "to_lat");
        var lng = ExtraDouble(extra, "to_lng");
        if (lat is null or 0 || lng is null or 0)
        {
            var geo = await GeocodeAsync(address, ct);
            if (geo != null)
            {
                lat = geo.Value.Lat;
                lng = geo.Value.Lng;
            }
        }

        var point = new Dictionary<string, object?>
        {
            ["address"] = address,
            ["name"] = string.IsNullOrWhiteSpace(name) ? "Khách" : name,
            ["mobile"] = NormalizeVnMobile(mobile) ?? mobile,
            ["cod"] = (int)Math.Max(0, cod),
        };
        if (!string.IsNullOrWhiteSpace(tracking))
            point["tracking_number"] = tracking;
        if (lat is > 0 && lng is > 0)
        {
            point["lat"] = lat;
            point["lng"] = lng;
        }
        return point;
    }

    static (bool UseGroup, string Code) ResolveService(Dictionary<string, JsonElement>? extra, string? overrideCode)
    {
        var raw = (overrideCode ?? ExtraString(extra, "service_id") ?? ExtraString(extra, "group_service_id") ?? "BIKE")
            .Trim();
        if (raw.Contains('-', StringComparison.Ordinal) && !raw.StartsWith("VNM-", StringComparison.OrdinalIgnoreCase))
            return (false, raw);
        return (true, raw);
    }

    async Task<HttpResponseMessage> SendAuthAsync(
        PosShippingCarrierSetting settings, HttpMethod method, string path, object? body, CancellationToken ct)
    {
        var http = httpClientFactory.CreateClient("shipping-ahamove");
        using var req = new HttpRequestMessage(method, $"{BaseUrl(settings)}{path}");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", (settings.Password ?? "").Trim());
        if (body != null)
            req.Content = new StringContent(JsonSerializer.Serialize(body, JsonOpts), Encoding.UTF8, "application/json");
        return await http.SendAsync(req, ct);
    }

    async Task<HttpResponseMessage> PostAuthAsync(
        PosShippingCarrierSetting settings, string path, object body, CancellationToken ct) =>
        await SendAuthAsync(settings, HttpMethod.Post, path, body, ct);

    async Task<(bool Ok, HttpResponseMessage? Res, string Raw, string? Error)> SendAuthRetryAsync(
        PosShippingCarrierSetting settings, HttpMethod method, string path, object? body, CancellationToken ct)
    {
        var (ok, err) = await EnsureUserTokenAsync(settings, ct);
        if (!ok)
            return (false, null, "", err ?? "Không lấy được token AhaMove.");

        var res = await SendAuthAsync(settings, method, path, body, ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        if (res.StatusCode != System.Net.HttpStatusCode.Unauthorized)
            return (true, res, raw, null);

        res.Dispose();
        settings.Password = null;
        var retry = await EnsureUserTokenAsync(settings, ct);
        if (!retry.Ok)
            return (false, null, "", retry.Error ?? "Token AhaMove hết hạn.");
        res = await SendAuthAsync(settings, method, path, body, ct);
        raw = await res.Content.ReadAsStringAsync(ct);
        return (true, res, raw, null);
    }

    public async Task<ShippingQuoteResult> QuoteAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, CancellationToken ct = default)
    {
        var (ok, err) = await EnsureUserTokenAsync(settings, ct);
        if (!ok)
            return new(false, CarrierCode, 0, Message: err);

        var extra = ParseExtra(settings.ExtraJson);
        var pickup = await BuildPickupPathAsync(settings, extra, ct);
        var dropAddress = ComposeDropoffAddress(
            request.ToAddress, request.ToWard, request.ToDistrict, request.ToProvince);
        if (string.IsNullOrWhiteSpace(dropAddress))
            return new(false, CarrierCode, 0, Message: "AhaMove cần địa chỉ nhận (số nhà, đường, phường, tỉnh).");

        var drop = await BuildDropoffPathAsync(
            extra, dropAddress, request.ToName, request.ToPhone, request.CodAmount, null, ct);
        var (useGroup, serviceCode) = ResolveService(extra, null);

        var payload = new Dictionary<string, object?>
        {
            ["order_time"] = 0,
            ["path"] = new[] { pickup, drop },
            ["payment_method"] = "BALANCE",
        };
        if (useGroup)
        {
            payload["group_services"] = new[]
            {
                new Dictionary<string, object?>
                {
                    ["_id"] = serviceCode,
                    ["group_requests"] = Array.Empty<object>(),
                },
            };
        }
        else
        {
            payload["services"] = new[]
            {
                new Dictionary<string, object?>
                {
                    ["_id"] = serviceCode,
                    ["requests"] = Array.Empty<object>(),
                },
            };
        }

        try
        {
            using var res = await PostAuthAsync(settings, "/v3/orders/estimates", payload, ct);
            if (res.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            {
                settings.Password = null;
                var retry = await EnsureUserTokenAsync(settings, ct);
                if (!retry.Ok)
                    return new(false, CarrierCode, 0, Message: retry.Error);
                using var res2 = await PostAuthAsync(settings, "/v3/orders/estimates", payload, ct);
                return ParseEstimate(res2, serviceCode, await res2.Content.ReadAsStringAsync(ct));
            }

            var raw = await res.Content.ReadAsStringAsync(ct);
            return ParseEstimate(res, serviceCode, raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "AhaMove quote failed");
            return new(false, CarrierCode, 0, Message: ex.Message);
        }
    }

    ShippingQuoteResult ParseEstimate(HttpResponseMessage res, string serviceCode, string raw)
    {
        try
        {
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            decimal fee = 0;
            string? usedService = serviceCode;

            JsonElement row = default;
            var hasRow = false;
            if (root.ValueKind == JsonValueKind.Array && root.GetArrayLength() > 0)
            {
                row = root[0];
                hasRow = true;
            }
            else if (root.TryGetProperty("data", out var data) &&
                     data.ValueKind == JsonValueKind.Array && data.GetArrayLength() > 0)
            {
                row = data[0];
                hasRow = true;
            }

            if (hasRow)
            {
                if (row.TryGetProperty("service_id", out var sid))
                    usedService = sid.GetString() ?? usedService;
                var blob = row.TryGetProperty("data", out var inner) ? inner : row;
                if (blob.TryGetProperty("total_price", out var tp)) fee = tp.GetDecimal();
                else if (blob.TryGetProperty("total_fee", out var tf)) fee = tf.GetDecimal();
            }
            else if (root.TryGetProperty("total_price", out var tp3))
                fee = tp3.GetDecimal();

            if (fee <= 0 && !res.IsSuccessStatusCode)
                return new(false, CarrierCode, 0, Message: ReadError(root, raw), RawJson: raw);

            if (fee < 0)
                return new(false, CarrierCode, 0, Message: ReadError(root, raw), RawJson: raw);

            return new(true, CarrierCode, fee, ServiceName: usedService, ServiceCode: usedService, RawJson: raw);
        }
        catch
        {
            return new(false, CarrierCode, 0, Message: raw, RawJson: raw);
        }
    }

    public async Task<ShippingCreateResult> CreateAsync(
        PosShippingCarrierSetting settings, PosSaleOrder order, ShippingCreateRequest request,
        CancellationToken ct = default)
    {
        var (ok, err) = await EnsureUserTokenAsync(settings, ct);
        if (!ok)
            return new(false, CarrierCode, Message: err);

        var extra = ParseExtra(settings.ExtraJson);
        var pickup = await BuildPickupPathAsync(settings, extra, ct);
        pickup["remarks"] = $"SBOX {order.OrderNo}";

        var dropAddress = ComposeDropoffAddress(
            order.DeliveryAddress,
            request.ToWard ?? order.DeliveryWard,
            request.ToDistrict ?? order.DeliveryDistrict,
            request.ToProvince ?? order.DeliveryProvince);
        if (string.IsNullOrWhiteSpace(dropAddress))
            return new(false, CarrierCode, Message: "AhaMove cần địa chỉ giao đầy đủ.");

        var drop = await BuildDropoffPathAsync(
            extra,
            dropAddress,
            order.CustomerName ?? "Khách",
            order.DeliveryPhone ?? "",
            request.CodAmount ?? 0,
            order.OrderNo,
            ct);
        if (request.ToLat is > 0 && request.ToLng is > 0)
        {
            drop["lat"] = request.ToLat.Value;
            drop["lng"] = request.ToLng.Value;
        }

        var (useGroup, serviceCode) = ResolveService(extra, request.ServiceCode);
        var pay = ShippingFeePayer.ShopPaysCarrier(request.ShipFeePayer) ? "BALANCE" : "CASH";

        var payload = new Dictionary<string, object?>
        {
            ["order_time"] = 0,
            ["path"] = new[] { pickup, drop },
            ["payment_method"] = pay,
            ["remarks"] = request.Note ?? order.Note ?? $"SBOX {order.OrderNo}",
        };
        if (useGroup) payload["group_service_id"] = serviceCode;
        else payload["service_id"] = serviceCode;

        var items = order.Lines?
            .Where(l => l.Deleted == null)
            .Select((l, i) => new Dictionary<string, object?>
            {
                ["_id"] = string.IsNullOrWhiteSpace(l.ProductId.ToString()) ? $"L{i + 1}" : l.ProductId.ToString("N")[..8],
                ["name"] = string.IsNullOrWhiteSpace(l.ProductName) ? "Hàng" : l.ProductName,
                ["num"] = Math.Max(1, (int)Math.Round(l.Qty)),
                ["price"] = (int)Math.Max(0, l.UnitPrice),
            })
            .ToList();
        if (items is { Count: > 0 })
            payload["items"] = items;

        try
        {
            using var res = await PostAuthAsync(settings, "/v3/orders", payload, ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            if (res.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            {
                settings.Password = null;
                var retry = await EnsureUserTokenAsync(settings, ct);
                if (!retry.Ok)
                    return new(false, CarrierCode, Message: retry.Error);
                using var res2 = await PostAuthAsync(settings, "/v3/orders", payload, ct);
                raw = await res2.Content.ReadAsStringAsync(ct);
                return ParseCreate(raw);
            }
            return ParseCreate(raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "AhaMove create failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    ShippingCreateResult ParseCreate(string raw)
    {
        try
        {
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            string? orderId = null;
            decimal? fee = null;
            string? link = null;
            if (root.TryGetProperty("order_id", out var oid)) orderId = oid.GetString();
            else if (root.TryGetProperty("_id", out var idAlt)) orderId = idAlt.GetString();
            else if (root.TryGetProperty("data", out var data))
            {
                if (data.TryGetProperty("order_id", out var oid2)) orderId = oid2.GetString();
                else if (data.TryGetProperty("_id", out var id2)) orderId = id2.GetString();
            }
            if (root.TryGetProperty("shared_link", out var sl)) link = sl.GetString();
            if (root.TryGetProperty("total_price", out var tp)) fee = tp.GetDecimal();
            else if (root.TryGetProperty("order", out var ord) && ord.TryGetProperty("total_price", out var tp2))
                fee = tp2.GetDecimal();
            else if (root.TryGetProperty("data", out var d2) && d2.TryGetProperty("total_price", out var tp3))
                fee = tp3.GetDecimal();

            if (string.IsNullOrWhiteSpace(orderId))
                return new(false, CarrierCode, Message: ReadError(root, raw), RawJson: raw);

            return new(true, CarrierCode,
                TrackingCode: orderId, CarrierOrderId: orderId,
                Fee: fee, LabelUrl: link,
                Message: "Tạo đơn AhaMove thành công", RawJson: raw);
        }
        catch
        {
            return new(false, CarrierCode, Message: raw, RawJson: raw);
        }
    }

    public async Task<ShippingCancelResult> CancelOrderAsync(
        PosShippingCarrierSetting settings, string orderId, string? note, CancellationToken ct = default)
    {
        var id = (orderId ?? "").Trim();
        if (id.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã đơn AhaMove");
        var comment = string.IsNullOrWhiteSpace(note) ? "Khách hàng muốn hủy đơn" : note.Trim();
        try
        {
            var (ok, res, raw, err) = await SendAuthRetryAsync(
                settings, HttpMethod.Delete, $"/v3/orders/{Uri.EscapeDataString(id)}",
                new { comment }, ct);
            if (!ok)
                return new(false, CarrierCode, Message: err);
            using (res)
            {
                return ParseCancel(res!, raw);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "AhaMove cancel failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    ShippingCancelResult ParseCancel(HttpResponseMessage res, string raw)
    {
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;
            var status = ReadStatus(root);
            if (res.IsSuccessStatusCode ||
                string.Equals(status, "CANCELLED", StringComparison.OrdinalIgnoreCase))
                return new(true, CarrierCode, Message: "Đã hủy vận đơn AhaMove");

            var title = root.TryGetProperty("title", out var t) ? t.GetString() : null;
            if (string.Equals(title, "ORDER_CANCELLED", StringComparison.OrdinalIgnoreCase) ||
                (ReadError(root, "").Contains("CANCEL", StringComparison.OrdinalIgnoreCase) &&
                 res.StatusCode is System.Net.HttpStatusCode.BadRequest or System.Net.HttpStatusCode.Conflict))
                return new(true, CarrierCode, Message: "Đơn AhaMove đã hủy trước đó");

            return new(false, CarrierCode, Message: ReadError(root, raw));
        }
        catch
        {
            return res.IsSuccessStatusCode
                ? new(true, CarrierCode, Message: "Đã hủy vận đơn AhaMove")
                : new(false, CarrierCode, Message: raw);
        }
    }

    public async Task<ShippingTrackingResult> GetTrackingAsync(
        PosShippingCarrierSetting settings, string orderId, CancellationToken ct = default)
    {
        var id = (orderId ?? "").Trim();
        if (id.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã đơn AhaMove");
        try
        {
            var (ok, res, raw, err) = await SendAuthRetryAsync(
                settings, HttpMethod.Get, $"/v3/orders/{Uri.EscapeDataString(id)}", null, ct);
            if (!ok)
                return new(false, CarrierCode, Message: err);
            using (res)
            {
                return ParseTracking(raw);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "AhaMove tracking failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    ShippingTrackingResult ParseTracking(string raw)
    {
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;
            if (root.TryGetProperty("order", out var nested) && nested.ValueKind == JsonValueKind.Object)
                root = nested;
            var status = ReadStatus(root);
            if (string.IsNullOrWhiteSpace(status) &&
                root.TryGetProperty("title", out _))
                return new(false, CarrierCode, Message: ReadError(root, raw), RawJson: raw);

            var display = AhamoveWebhookHelper.DisplayName(status);
            var mapped = AhamoveWebhookHelper.MapOnlineStatus(status);
            return new(
                true, CarrierCode,
                StatusName: display,
                MappedOnlineStatus: mapped,
                Events: BuildTrackingEvents(root, status, display),
                Message: display,
                RawJson: raw);
        }
        catch
        {
            return new(false, CarrierCode, Message: raw, RawJson: raw);
        }
    }

    static string? ReadStatus(JsonElement root)
    {
        if (root.TryGetProperty("status", out var s) && s.ValueKind == JsonValueKind.String)
            return s.GetString();
        if (root.TryGetProperty("order", out var order) && order.ValueKind == JsonValueKind.Object
            && order.TryGetProperty("status", out var s2) && s2.ValueKind == JsonValueKind.String)
            return s2.GetString();
        return null;
    }

    static List<ShippingTrackingEvent> BuildTrackingEvents(JsonElement root, string? status, string? display)
    {
        var events = new List<ShippingTrackingEvent>();
        void Try(string timeKey, string name)
        {
            var when = FormatUnix(root, timeKey);
            if (string.IsNullOrWhiteSpace(when)) return;
            events.Add(new ShippingTrackingEvent(null, name, when, ReadLocation(root), null));
        }

        Try("create_time", "Đã tạo đơn");
        Try("accept_time", "Tài xế nhận đơn");
        Try("pickup_time", "Đã lấy hàng");
        Try("complete_time", "Đã giao");
        Try("cancel_time", "Đã hủy");
        if (events.Count == 0)
            events.Add(new ShippingTrackingEvent(null, display ?? status, null, ReadLocation(root), status));
        return events;
    }

    static string? ReadLocation(JsonElement root)
    {
        if (root.TryGetProperty("path", out var path) && path.ValueKind == JsonValueKind.Array
            && path.GetArrayLength() > 0)
        {
            var last = path[path.GetArrayLength() - 1];
            if (last.TryGetProperty("address", out var addr) && addr.ValueKind == JsonValueKind.String)
                return addr.GetString();
        }
        return root.TryGetProperty("supplier_name", out var n) && n.ValueKind == JsonValueKind.String
            ? n.GetString()
            : null;
    }

    static string? FormatUnix(JsonElement root, string key)
    {
        if (!root.TryGetProperty(key, out var el)) return null;
        double unix = 0;
        if (el.ValueKind == JsonValueKind.Number && el.TryGetDouble(out var d)) unix = d;
        else if (el.ValueKind == JsonValueKind.String &&
                 double.TryParse(el.GetString(), System.Globalization.NumberStyles.Float,
                     System.Globalization.CultureInfo.InvariantCulture, out var p))
            unix = p;
        if (unix <= 1_000_000) return null;
        var dt = DateTimeOffset.FromUnixTimeSeconds((long)unix).ToOffset(TimeSpan.FromHours(7));
        return dt.ToString("yyyy-MM-dd HH:mm", System.Globalization.CultureInfo.InvariantCulture);
    }
}
