using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>
/// SPX Express (Shopee Express VN) — User ID + Secret Key (Hồ sơ Shop).
/// Open API HMAC-SHA256: sign = HMAC(userId + timestamp + body, secret).
/// Tra cứu công khai: GET /api/v2/fleet_order/tracking/search?sls_tn=
/// </summary>
public class SpxShippingClient(IHttpClientFactory httpClientFactory, ILogger<SpxShippingClient> logger)
    : IShippingCarrierClient
{
    public string CarrierCode => ShippingCarrierCodes.Spx;

    const string PublicTrackingHost = "https://spx.vn";
    static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    string OpenApiBase(PosShippingCarrierSetting s)
    {
        if (!string.IsNullOrWhiteSpace(s.ApiBaseUrl)) return s.ApiBaseUrl.Trim().TrimEnd('/');
        var fromExtra = SpxExtraJson.ReadString(s.ExtraJson, "apiBaseUrl", "api_base_url", "baseUrl");
        if (!string.IsNullOrWhiteSpace(fromExtra)) return fromExtra.Trim().TrimEnd('/');
        return s.UseSandbox ? "https://test-stable.spx.vn" : "https://spx.vn";
    }

    static string OpenApiPrefix(PosShippingCarrierSetting s) =>
        SpxExtraJson.GetOpenApiPrefix(s.ExtraJson) ?? "/open/api/v1";

    static string? UserId(PosShippingCarrierSetting s) =>
        string.IsNullOrWhiteSpace(s.ShopId) ? null : s.ShopId.Trim();

    static string? Secret(PosShippingCarrierSetting s) =>
        string.IsNullOrWhiteSpace(s.ApiToken) ? null : s.ApiToken.Trim();

    static string HmacSign(string userId, string timestamp, string body, string secret)
    {
        var msg = userId + timestamp + (body ?? "");
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(msg));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    HttpClient Client() => httpClientFactory.CreateClient("shipping-spx");

    async Task<(HttpResponseMessage Res, string Raw)> PostSignedAsync(
        PosShippingCarrierSetting settings, string path, object payload, CancellationToken ct)
    {
        var userId = UserId(settings)!;
        var secret = Secret(settings)!;
        var body = JsonSerializer.Serialize(payload, JsonOpts);
        var ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture);
        var sign = HmacSign(userId, ts, body, secret);
        var url = $"{OpenApiBase(settings)}{path}";

        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Content = new StringContent(body, Encoding.UTF8, "application/json");
        req.Headers.TryAddWithoutValidation("app-id", userId);
        req.Headers.TryAddWithoutValidation("timestamp", ts);
        req.Headers.TryAddWithoutValidation("sign", sign);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        var http = Client();
        var res = await http.SendAsync(req, ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        return (res, raw);
    }

    static bool LooksLikeHtml(string raw) =>
        raw.StartsWith("<!", StringComparison.OrdinalIgnoreCase) ||
        raw.Contains("<html", StringComparison.OrdinalIgnoreCase);

    static bool IsOpenApiSuccess(JsonElement root, out JsonElement data)
    {
        data = default;
        if (root.TryGetProperty("data", out var d) && d.ValueKind is JsonValueKind.Object or JsonValueKind.Array)
            data = d;
        else
            data = root;

        if (root.TryGetProperty("retcode", out var rc))
        {
            if (rc.ValueKind == JsonValueKind.Number && rc.TryGetInt32(out var n)) return n == 0;
            if (rc.ValueKind == JsonValueKind.String && int.TryParse(rc.GetString(), out var ns)) return ns == 0;
        }
        if (root.TryGetProperty("code", out var c))
        {
            if (c.ValueKind == JsonValueKind.Number && c.TryGetInt32(out var n) && n is 0 or 200) return true;
            if (c.ValueKind == JsonValueKind.String &&
                (c.GetString() is "0" or "200" or "success")) return true;
        }
        if (root.TryGetProperty("success", out var ok) &&
            ok.ValueKind == JsonValueKind.True) return true;
        return false;
    }

    static string ReadError(JsonElement root, string raw)
    {
        foreach (var key in new[] { "message", "msg", "error", "error_msg", "retmsg" })
        {
            if (root.TryGetProperty(key, out var el) && el.ValueKind == JsonValueKind.String)
            {
                var s = el.GetString();
                if (!string.IsNullOrWhiteSpace(s)) return s!;
            }
        }
        return LooksLikeHtml(raw)
            ? "SPX Open API chưa phản hồi JSON — kiểm tra User ID / Secret Key đã kích hoạt API, hoặc điền Api Base URL do SPX cấp."
            : (raw.Length > 400 ? raw[..400] : raw);
    }

    static decimal? ReadDecimal(JsonElement obj, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (!obj.TryGetProperty(key, out var el)) continue;
            if (el.ValueKind == JsonValueKind.Number && el.TryGetDecimal(out var d)) return d;
            if (el.ValueKind == JsonValueKind.String &&
                decimal.TryParse(el.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var p))
                return p;
        }
        return null;
    }

    static string? ReadString(JsonElement obj, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (!obj.TryGetProperty(key, out var el)) continue;
            var s = el.ValueKind == JsonValueKind.String ? el.GetString() : el.ToString();
            if (!string.IsNullOrWhiteSpace(s)) return s.Trim();
        }
        return null;
    }

    static Dictionary<string, object?> AddressBlock(
        string name, string phone, string address, string? province, string? district, string? ward)
    {
        return new Dictionary<string, object?>
        {
            ["name"] = name,
            ["phone"] = phone,
            ["detail_address"] = address,
            ["state"] = province ?? "",
            ["city"] = string.IsNullOrWhiteSpace(district) ? (ward ?? "") : district,
            ["district"] = ward ?? district ?? "",
            ["province"] = province ?? "",
            ["ward"] = ward ?? "",
        };
    }

    Dictionary<string, object?> BuildOrderPayload(
        PosShippingCarrierSetting settings,
        string orderId,
        string toName, string toPhone, string toAddress,
        string? toProvince, string? toDistrict, string? toWard,
        int weightGrams, int lengthCm, int widthCm, int heightCm,
        decimal cod, decimal insurance, string? note)
    {
        var recv = ShippingAddressNormalizer.Normalize(toAddress, toProvince, toDistrict, toWard);
        var inspect = SpxExtraJson.GetBool(settings.ExtraJson, SpxExtraJson.AllowInspectKey);
        var partial = SpxExtraJson.GetBool(settings.ExtraJson, SpxExtraJson.PartialDeliveryKey);
        var useIns = SpxExtraJson.GetBool(settings.ExtraJson, SpxExtraJson.UseInsuranceKey, insurance > 0);
        var service = SpxExtraJson.ReadString(settings.ExtraJson, SpxExtraJson.ServiceTypeKey, "service_type");

        return new Dictionary<string, object?>
        {
            ["user_id"] = UserId(settings),
            ["order_id"] = orderId,
            ["sender_name"] = settings.PickupName ?? "Cửa hàng",
            ["sender_phone"] = settings.PickupPhone ?? "",
            ["sender_detail_address"] = settings.PickupAddress ?? "",
            ["sender_address"] = settings.PickupAddress ?? "",
            ["sender_state"] = settings.FromProvinceName ?? "",
            ["sender_province"] = settings.FromProvinceName ?? "",
            ["sender_city"] = settings.FromDistrictName ?? settings.FromWardName ?? "",
            ["sender_district"] = settings.FromWardName ?? settings.FromDistrictName ?? "",
            ["sender_ward"] = settings.FromWardName ?? "",
            ["deliver_name"] = toName,
            ["receiver_name"] = toName,
            ["deliver_phone"] = toPhone,
            ["receiver_phone"] = toPhone,
            ["deliver_detail_address"] = string.IsNullOrWhiteSpace(recv.Address) ? toAddress : recv.Address,
            ["receiver_address"] = string.IsNullOrWhiteSpace(recv.Address) ? toAddress : recv.Address,
            ["deliver_state"] = recv.Province ?? "",
            ["receiver_province"] = recv.Province ?? "",
            ["deliver_city"] = recv.District ?? recv.Ward ?? "",
            ["receiver_district"] = recv.District ?? "",
            ["deliver_district"] = recv.Ward ?? recv.District ?? "",
            ["receiver_ward"] = recv.Ward ?? "",
            ["cod_collection"] = (long)Math.Max(0, Math.Round(cod)),
            ["cod_amount"] = (long)Math.Max(0, Math.Round(cod)),
            ["parcel_weight"] = Math.Max(1, weightGrams),
            ["weight"] = Math.Max(1, weightGrams),
            ["parcel_length"] = Math.Max(1, lengthCm),
            ["parcel_width"] = Math.Max(1, widthCm),
            ["parcel_height"] = Math.Max(1, heightCm),
            ["length"] = Math.Max(1, lengthCm),
            ["width"] = Math.Max(1, widthCm),
            ["height"] = Math.Max(1, heightCm),
            ["express_insured_value"] = useIns ? (long)Math.Max(0, Math.Round(insurance)) : 0,
            ["insurance_value"] = useIns ? (long)Math.Max(0, Math.Round(insurance)) : 0,
            ["item_name"] = string.IsNullOrWhiteSpace(note) ? $"Đơn {orderId}" : note,
            ["item_quantity"] = 1,
            ["remark"] = note ?? "",
            ["allow_try_on"] = inspect,
            ["partial_delivery"] = partial,
            ["service_type"] = service,
            ["sender"] = AddressBlock(
                settings.PickupName ?? "Cửa hàng",
                settings.PickupPhone ?? "",
                settings.PickupAddress ?? "",
                settings.FromProvinceName, settings.FromDistrictName, settings.FromWardName),
            ["deliver"] = AddressBlock(
                toName, toPhone,
                string.IsNullOrWhiteSpace(recv.Address) ? toAddress : recv.Address!,
                recv.Province, recv.District, recv.Ward),
        };
    }

    static string MissingCreds() =>
        "Thiếu User ID hoặc Secret Key SPX (Hồ sơ Shop trên spx.vn)";

    public async Task<ShippingQuoteResult> QuoteAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(UserId(settings)) || string.IsNullOrWhiteSpace(Secret(settings)))
            return new(false, CarrierCode, 0, Message: MissingCreds());
        if (string.IsNullOrWhiteSpace(settings.FromProvinceName))
            return new(false, CarrierCode, 0, Message: "Thiếu tỉnh/thành lấy hàng SPX");

        var recv = ShippingAddressNormalizer.Normalize(
            request.ToAddress, request.ToProvince, request.ToDistrict, request.ToWard);
        if (string.IsNullOrWhiteSpace(recv.Province))
            return new(false, CarrierCode, 0, Message: "Thiếu tỉnh/thành nhận hàng");

        var payload = new Dictionary<string, object?>
        {
            ["user_id"] = UserId(settings),
            ["sender_state"] = settings.FromProvinceName,
            ["sender_province"] = settings.FromProvinceName,
            ["sender_city"] = settings.FromDistrictName ?? settings.FromWardName ?? "",
            ["sender_district"] = settings.FromWardName ?? settings.FromDistrictName ?? "",
            ["deliver_state"] = recv.Province,
            ["receiver_province"] = recv.Province,
            ["deliver_city"] = recv.District ?? recv.Ward ?? "",
            ["receiver_district"] = recv.District ?? "",
            ["deliver_district"] = recv.Ward ?? recv.District ?? "",
            ["receiver_ward"] = recv.Ward ?? "",
            ["parcel_weight"] = Math.Max(1, request.WeightGrams),
            ["weight"] = Math.Max(1, request.WeightGrams),
            ["parcel_length"] = Math.Max(1, request.LengthCm),
            ["parcel_width"] = Math.Max(1, request.WidthCm),
            ["parcel_height"] = Math.Max(1, request.HeightCm),
            ["cod_collection"] = (long)Math.Max(0, Math.Round(request.CodAmount)),
            ["cod_amount"] = (long)Math.Max(0, Math.Round(request.CodAmount)),
            ["express_insured_value"] = (long)Math.Max(0, Math.Round(request.InsuranceValue)),
            ["sender"] = AddressBlock(
                settings.PickupName ?? "Cửa hàng", settings.PickupPhone ?? "",
                settings.PickupAddress ?? "",
                settings.FromProvinceName, settings.FromDistrictName, settings.FromWardName),
            ["deliver"] = AddressBlock(
                request.ToName, request.ToPhone,
                string.IsNullOrWhiteSpace(recv.Address) ? request.ToAddress : recv.Address!,
                recv.Province, recv.District, recv.Ward),
        };

        var prefix = OpenApiPrefix(settings);
        try
        {
            var (res, raw) = await PostSignedAsync(settings, $"{prefix}/order/check_fee", payload, ct);
            if (LooksLikeHtml(raw) || (int)res.StatusCode is 404 or 405)
            {
                (res, raw) = await PostSignedAsync(settings, $"{prefix}/order/fee", payload, ct);
            }
            using (res)
            {
                if (LooksLikeHtml(raw) || (int)res.StatusCode is 404 or 405)
                    return new(false, CarrierCode, 0,
                        Message: "SPX chưa mở Open API trên host mặc định. Điền Api Base URL / prefix do SPX cấp (Hồ sơ Shop → tài liệu API), rồi Thử kết nối lại.",
                        RawJson: raw.Length > 500 ? raw[..500] : raw);

                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
                var root = doc.RootElement;
                if (!IsOpenApiSuccess(root, out var data))
                    return new(false, CarrierCode, 0, Message: ReadError(root, raw), RawJson: raw);

                var fee = ReadDecimal(data, "total_fee", "shipping_fee", "fee", "estimated_fee", "total")
                          ?? ReadDecimal(root, "total_fee", "shipping_fee", "fee");
                if (data.ValueKind == JsonValueKind.Array && data.GetArrayLength() > 0)
                    fee ??= ReadDecimal(data[0], "total_fee", "shipping_fee", "fee", "estimated_fee");

                return new(true, CarrierCode, fee ?? 0,
                    ServiceName: "SPX Express",
                    ServiceCode: SpxExtraJson.ReadString(settings.ExtraJson, SpxExtraJson.ServiceTypeKey) ?? "standard",
                    RawJson: raw);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "SPX quote failed");
            return new(false, CarrierCode, 0, Message: ex.Message);
        }
    }

    public async Task<ShippingCreateResult> CreateAsync(
        PosShippingCarrierSetting settings, PosSaleOrder order, ShippingCreateRequest request,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(UserId(settings)) || string.IsNullOrWhiteSpace(Secret(settings)))
            return new(false, CarrierCode, Message: MissingCreds());

        var toPhone = order.DeliveryPhone ?? "";
        var toAddress = order.DeliveryAddress ?? "";
        if (string.IsNullOrWhiteSpace(toPhone) || string.IsNullOrWhiteSpace(toAddress))
            return new(false, CarrierCode, Message: "Đơn thiếu SĐT / địa chỉ giao");

        var province = request.ToProvince ?? order.DeliveryProvince;
        var district = request.ToDistrict ?? order.DeliveryDistrict;
        var ward = request.ToWard ?? order.DeliveryWard;
        var line = BuildOrderPayload(
            settings, order.OrderNo,
            order.CustomerName ?? "Khách", toPhone, toAddress,
            province, district, ward,
            request.WeightGrams, request.LengthCm, request.WidthCm, request.HeightCm,
            request.CodAmount ?? 0,
            order.PayableTotal,
            request.Note ?? order.Note ?? $"SBOX {order.OrderNo}");

        var payload = new Dictionary<string, object?>
        {
            ["user_id"] = UserId(settings),
            ["orders"] = new[] { line },
        };
        foreach (var kv in line)
            payload.TryAdd(kv.Key, kv.Value);

        var prefix = OpenApiPrefix(settings);
        try
        {
            var (res, raw) = await PostSignedAsync(settings, $"{prefix}/order", payload, ct);
            if (LooksLikeHtml(raw) || (int)res.StatusCode is 404 or 405)
                (res, raw) = await PostSignedAsync(settings, $"{prefix}/order/create", payload, ct);
            using (res)
            {
                if (LooksLikeHtml(raw) || (int)res.StatusCode is 404 or 405)
                    return new(false, CarrierCode,
                        Message: "SPX chưa mở Open API tạo đơn trên host mặc định. Điền Api Base URL do SPX cấp rồi thử lại.",
                        RawJson: raw.Length > 500 ? raw[..500] : raw);

                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
                var root = doc.RootElement;
                if (!IsOpenApiSuccess(root, out var data))
                    return new(false, CarrierCode, Message: ReadError(root, raw), RawJson: raw);

                var first = data;
                if (data.ValueKind == JsonValueKind.Array && data.GetArrayLength() > 0)
                    first = data[0];
                if (first.TryGetProperty("orders", out var orders) &&
                    orders.ValueKind == JsonValueKind.Array && orders.GetArrayLength() > 0)
                    first = orders[0];

                var tracking = ReadString(first, "tracking_number", "sls_tn", "tracking_no",
                    "shipment_id", "order_id", "spx_tn")
                    ?? ReadString(root, "tracking_number", "sls_tn");
                if (string.IsNullOrWhiteSpace(tracking))
                    return new(false, CarrierCode, Message: ReadError(root, raw), RawJson: raw);

                var fee = ReadDecimal(first, "total_fee", "shipping_fee", "fee")
                          ?? ReadDecimal(root, "total_fee", "shipping_fee", "fee");
                var label = ReadString(first, "awb_url", "label_url", "print_url")
                            ?? PublicTrackUrl(tracking);

                return new(true, CarrierCode,
                    TrackingCode: tracking, CarrierOrderId: tracking,
                    LabelUrl: label, Fee: fee,
                    Message: "Tạo vận đơn SPX thành công", RawJson: raw);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "SPX create failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    public async Task<ShippingCancelResult> CancelOrderAsync(
        PosShippingCarrierSetting settings, string trackingCode, string? note, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(UserId(settings)) || string.IsNullOrWhiteSpace(Secret(settings)))
            return new(false, CarrierCode, Message: MissingCreds());
        var tn = trackingCode.Trim();
        if (tn.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã vận đơn SPX");

        var payload = new Dictionary<string, object?>
        {
            ["user_id"] = UserId(settings),
            ["tracking_number"] = tn,
            ["tracking_nos"] = new[] { tn },
            ["sls_tn"] = tn,
            ["reason"] = string.IsNullOrWhiteSpace(note) ? "Hủy từ SBOX" : note.Trim(),
        };
        var prefix = OpenApiPrefix(settings);
        try
        {
            var (res, raw) = await PostSignedAsync(settings, $"{prefix}/order/cancel", payload, ct);
            using (res)
            {
                if (LooksLikeHtml(raw) || (int)res.StatusCode is 404 or 405)
                    return new(false, CarrierCode, Message: "SPX Open API hủy đơn chưa khả dụng trên host hiện tại.");

                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
                var root = doc.RootElement;
                if (!IsOpenApiSuccess(root, out _))
                    return new(false, CarrierCode, Message: ReadError(root, raw));
                return new(true, CarrierCode, Message: "Đã hủy vận đơn SPX");
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "SPX cancel failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    public async Task<ShippingLabelResult> GetPrintLabelAsync(
        PosShippingCarrierSetting settings, string trackingCode, CancellationToken ct = default)
    {
        var tn = (trackingCode ?? "").Trim();
        if (tn.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã vận đơn SPX");

        if (!string.IsNullOrWhiteSpace(UserId(settings)) && !string.IsNullOrWhiteSpace(Secret(settings)))
        {
            var payload = new Dictionary<string, object?>
            {
                ["user_id"] = UserId(settings),
                ["tracking_number"] = tn,
                ["tracking_nos"] = new[] { tn },
                ["sls_tn"] = tn,
            };
            var prefix = OpenApiPrefix(settings);
            try
            {
                var (res, raw) = await PostSignedAsync(settings, $"{prefix}/order/print", payload, ct);
                using (res)
                {
                    if (!LooksLikeHtml(raw) && (int)res.StatusCode is not (404 or 405))
                    {
                        using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
                        var root = doc.RootElement;
                        if (IsOpenApiSuccess(root, out var data))
                        {
                            var url = ReadString(data, "awb_url", "label_url", "print_url", "url")
                                      ?? ReadString(root, "awb_url", "label_url", "print_url");
                            if (!string.IsNullOrWhiteSpace(url))
                                return new(true, CarrierCode, LabelUrl: url, Message: "Phiếu gửi SPX");
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "SPX print failed, fallback public URL");
            }
        }

        return new(true, CarrierCode, LabelUrl: PublicTrackUrl(tn),
            Message: "Link tra cứu / phiếu SPX");
    }

    public async Task<ShippingTrackingResult> GetTrackingAsync(
        PosShippingCarrierSetting settings, string trackingCode, CancellationToken ct = default)
    {
        var tn = (trackingCode ?? "").Trim();
        if (tn.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã vận đơn SPX");

        if (!string.IsNullOrWhiteSpace(UserId(settings)) && !string.IsNullOrWhiteSpace(Secret(settings)))
        {
            var open = await TryOpenApiTrackingAsync(settings, tn, ct);
            if (open != null) return open;
        }

        return await PublicTrackingAsync(tn, ct);
    }

    async Task<ShippingTrackingResult?> TryOpenApiTrackingAsync(
        PosShippingCarrierSetting settings, string tn, CancellationToken ct)
    {
        var payload = new Dictionary<string, object?>
        {
            ["user_id"] = UserId(settings),
            ["tracking_number"] = tn,
            ["sls_tn"] = tn,
            ["tracking_nos"] = new[] { tn },
        };
        var prefix = OpenApiPrefix(settings);
        try
        {
            var (res, raw) = await PostSignedAsync(settings, $"{prefix}/order/tracking", payload, ct);
            using (res)
            {
                if (LooksLikeHtml(raw) || (int)res.StatusCode is 404 or 405)
                    return null;
                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
                var root = doc.RootElement;
                if (!IsOpenApiSuccess(root, out var data))
                    return null;
                return ParseTrackingPayload(data, raw);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "SPX Open API tracking failed, fallback public");
            return null;
        }
    }

    async Task<ShippingTrackingResult> PublicTrackingAsync(string tn, CancellationToken ct)
    {
        try
        {
            var http = Client();
            var url = $"{PublicTrackingHost}/api/v2/fleet_order/tracking/search?sls_tn={Uri.EscapeDataString(tn)}";
            using var res = await http.GetAsync(url, ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            if (LooksLikeHtml(raw))
                return new(false, CarrierCode, Message: "SPX tracking công khai không trả JSON", RawJson: raw);

            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;
            if (!IsOpenApiSuccess(root, out var data))
                return new(false, CarrierCode, Message: ReadError(root, raw), RawJson: raw);

            if (data.ValueKind != JsonValueKind.Object || !data.EnumerateObject().Any())
                return new(false, CarrierCode, Message: "SPX chưa có hành trình cho mã này", RawJson: raw);

            return ParseTrackingPayload(data, raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "SPX public tracking failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    ShippingTrackingResult ParseTrackingPayload(JsonElement data, string raw)
    {
        var status = ReadString(data, "current_status", "status", "status_name", "status_code", "milestone");
        var events = new List<ShippingTrackingEvent>();
        foreach (var key in new[] { "tracking_list", "trackings", "events", "checkpoints", "history" })
        {
            if (!data.TryGetProperty(key, out var arr) || arr.ValueKind != JsonValueKind.Array) continue;
            foreach (var ev in arr.EnumerateArray())
            {
                var st = ReadString(ev, "status", "status_name", "milestone", "message", "description");
                var loc = ReadString(ev, "location", "hub", "city", "address");
                var time = ReadString(ev, "ctime", "time", "event_time", "timestamp", "created_at");
                if (ev.TryGetProperty("ctime", out var ctEl) && ctEl.ValueKind == JsonValueKind.Number
                    && ctEl.TryGetInt64(out var unix))
                    time = DateTimeOffset.FromUnixTimeSeconds(unix).ToLocalTime().ToString("yyyy-MM-dd HH:mm");
                events.Add(new ShippingTrackingEvent(null, st, time, loc, st));
            }
            break;
        }

        var display = SpxWebhookHelper.StatusLabel(status);
        return new(
            true, CarrierCode,
            StatusName: display,
            MappedOnlineStatus: SpxWebhookHelper.MapOnlineStatus(status),
            Events: events,
            Message: display,
            RawJson: raw);
    }

    public static string PublicTrackUrl(string tracking) =>
        $"https://spx.vn/track?id={Uri.EscapeDataString(tracking)}";
}
