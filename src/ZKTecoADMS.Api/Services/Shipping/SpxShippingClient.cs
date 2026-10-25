using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>
/// SPX Express (Shopee Express VN) — SPX Open Service Open API (tài liệu: https://spx.vn/integration).
/// Hai lớp khoá:
/// • app-id + app-secret (SPX cấp cho ứng dụng) → header ký mọi request:
///   app-id, timestamp (giây), random-num, check-sign = hex(HMAC-SHA256(app-secret, "{app_id}_{timestamp}_{random_num}_{body}")).
/// • user_id + user_secret (tài khoản shop) → gửi trong body JSON mọi API đơn hàng.
/// Cấu hình: ShopId = user_id · ApiToken = user_secret · ExtraJson appId/appSecret (hoặc Username/Password) = app-id/app-secret.
/// Mọi API là POST {host}/open/api/v1/...; phản hồi {"ret_code":0,"message","data"}.
/// Tra cứu công khai (dự phòng, không thuộc Open API): GET /api/v2/fleet_order/tracking/search?sls_tn=
/// </summary>
public class SpxShippingClient(IHttpClientFactory httpClientFactory, ILogger<SpxShippingClient> logger)
    : IShippingCarrierClient
{
    public string CarrierCode => ShippingCarrierCodes.Spx;

    const string PublicTrackingHost = "https://spx.vn";
    static readonly JsonSerializerOptions JsonOpts = new()
    {
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

    internal static string? AppId(PosShippingCarrierSetting s) =>
        SpxExtraJson.ReadString(s.ExtraJson, SpxExtraJson.AppIdKey, "app_id")
        ?? (string.IsNullOrWhiteSpace(s.Username) ? null : s.Username.Trim());

    internal static string? AppSecret(PosShippingCarrierSetting s) =>
        SpxExtraJson.ReadString(s.ExtraJson, SpxExtraJson.AppSecretKey, "app_secret")
        ?? (string.IsNullOrWhiteSpace(s.Password) ? null : s.Password.Trim());

    /// <summary>check-sign theo «API authentication guide» SPX.</summary>
    public static string ComputeCheckSign(string appId, string appSecret, long timestamp, long randomNum, string payload)
    {
        var msg = string.Format(CultureInfo.InvariantCulture, "{0}_{1}_{2}_{3}", appId, timestamp, randomNum, payload);
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(appSecret));
        return Convert.ToHexString(hmac.ComputeHash(Encoding.UTF8.GetBytes(msg))).ToLowerInvariant();
    }

    /// <summary>
    /// Webhook SPX: SPX ký body bằng app-secret, đặt ở header check-sign (cùng thuật toán với request).
    /// Giả định (docs không ghi rõ): timestamp + random-num đi kèm qua header như request thường.
    /// </summary>
    public static bool VerifyWebhookSign(
        PosShippingCarrierSetting s, string rawBody, string? checkSign, string? timestamp, string? randomNum)
    {
        var appId = AppId(s);
        var appSecret = AppSecret(s);
        if (string.IsNullOrWhiteSpace(appId) || string.IsNullOrWhiteSpace(appSecret)) return false;
        if (string.IsNullOrWhiteSpace(checkSign)) return false;
        if (!long.TryParse(timestamp, NumberStyles.Integer, CultureInfo.InvariantCulture, out var ts)) return false;
        if (!long.TryParse(randomNum, NumberStyles.Integer, CultureInfo.InvariantCulture, out var rnd)) return false;
        var expected = Encoding.ASCII.GetBytes(ComputeCheckSign(appId, appSecret, ts, rnd, rawBody ?? ""));
        var given = Encoding.ASCII.GetBytes(checkSign.Trim().ToLowerInvariant());
        return expected.Length == given.Length && CryptographicOperations.FixedTimeEquals(expected, given);
    }

    HttpClient Client() => httpClientFactory.CreateClient("shipping-spx");

    /// <summary>user_id là số nguyên (int64) theo docs; user_secret chuỗi.</summary>
    static Dictionary<string, object?> Credentials(PosShippingCarrierSetting s)
    {
        var uid = UserId(s)!;
        return new Dictionary<string, object?>
        {
            ["user_id"] = long.TryParse(uid, NumberStyles.Integer, CultureInfo.InvariantCulture, out var n)
                ? n : uid,
            ["user_secret"] = Secret(s),
        };
    }

    async Task<(HttpResponseMessage Res, string Raw)> PostSignedAsync(
        PosShippingCarrierSetting settings, string path, object payload, CancellationToken ct)
    {
        var appId = AppId(settings)!;
        var appSecret = AppSecret(settings)!;
        var body = JsonSerializer.Serialize(payload, JsonOpts);
        var ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var rnd = Random.Shared.NextInt64(1, 1_000_000_000);
        var sign = ComputeCheckSign(appId, appSecret, ts, rnd, body);
        var url = $"{OpenApiBase(settings)}{path}";

        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Content = new StringContent(body, Encoding.UTF8, "application/json");
        req.Headers.TryAddWithoutValidation("app-id", appId);
        req.Headers.TryAddWithoutValidation("timestamp", ts.ToString(CultureInfo.InvariantCulture));
        req.Headers.TryAddWithoutValidation("random-num", rnd.ToString(CultureInfo.InvariantCulture));
        req.Headers.TryAddWithoutValidation("check-sign", sign);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        var http = Client();
        var res = await http.SendAsync(req, ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        return (res, raw);
    }

    static bool LooksLikeHtml(string raw) =>
        raw.StartsWith("<!", StringComparison.OrdinalIgnoreCase) ||
        raw.Contains("<html", StringComparison.OrdinalIgnoreCase);

    /// <summary>Docs: ret_code = 0 là thành công (lỗi lô nằm ở data.fail_list[]).</summary>
    static bool IsOpenApiSuccess(JsonElement root, out JsonElement data)
    {
        data = root.TryGetProperty("data", out var d) && d.ValueKind is JsonValueKind.Object or JsonValueKind.Array
            ? d : root;
        foreach (var key in new[] { "ret_code", "retcode" })
        {
            if (!root.TryGetProperty(key, out var rc)) continue;
            if (rc.ValueKind == JsonValueKind.Number && rc.TryGetInt32(out var n)) return n == 0;
            if (rc.ValueKind == JsonValueKind.String && int.TryParse(rc.GetString(), out var ns)) return ns == 0;
        }
        // Tra cứu công khai spx.vn dùng retcode/code.
        if (root.TryGetProperty("code", out var c))
        {
            if (c.ValueKind == JsonValueKind.Number && c.TryGetInt32(out var n) && n is 0 or 200) return true;
            if (c.ValueKind == JsonValueKind.String && (c.GetString() is "0" or "200" or "success")) return true;
        }
        return root.TryGetProperty("success", out var ok) && ok.ValueKind == JsonValueKind.True;
    }

    static string ReadError(JsonElement root, string raw)
    {
        foreach (var key in new[] { "message", "msg", "error", "error_msg", "retmsg" })
        {
            if (root.TryGetProperty(key, out var el) && el.ValueKind == JsonValueKind.String)
            {
                var s = el.GetString();
                if (!string.IsNullOrWhiteSpace(s))
                {
                    var code = root.TryGetProperty("ret_code", out var rc) ? rc.ToString() : null;
                    return string.IsNullOrWhiteSpace(code) || code == "0" ? s!.Trim() : $"{s!.Trim()} (SPX {code})";
                }
            }
        }
        return LooksLikeHtml(raw)
            ? "SPX Open API chưa phản hồi JSON — kiểm tra app-id / User ID / Secret Key đã kích hoạt API, hoặc điền Api Base URL do SPX cấp."
            : (raw.Length > 400 ? raw[..400] : raw);
    }

    /// <summary>Lỗi đầu tiên trong data.fail_list[] (lỗi từng đơn của API lô).</summary>
    static string? FirstFail(JsonElement data)
    {
        if (data.ValueKind != JsonValueKind.Object ||
            !data.TryGetProperty("fail_list", out var fl) || fl.ValueKind != JsonValueKind.Array ||
            fl.GetArrayLength() == 0)
            return null;
        var f = fl[0];
        var msg = ReadString(f, "message", "debug_msg") ?? "SPX từ chối đơn";
        var code = ReadString(f, "ret_code");
        return code == null ? msg : $"{msg} (SPX {code})";
    }

    static JsonElement? FirstOrder(JsonElement data)
    {
        if (data.ValueKind == JsonValueKind.Object &&
            data.TryGetProperty("orders", out var orders) &&
            orders.ValueKind == JsonValueKind.Array && orders.GetArrayLength() > 0)
            return orders[0];
        return null;
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
        if (obj.ValueKind != JsonValueKind.Object) return null;
        foreach (var key in keys)
        {
            if (!obj.TryGetProperty(key, out var el)) continue;
            if (el.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) continue;
            var s = el.ValueKind == JsonValueKind.String ? el.GetString() : el.ToString();
            if (!string.IsNullOrWhiteSpace(s)) return s.Trim();
        }
        return null;
    }

    /// <summary>
    /// Khối địa chỉ VN theo docs: *_state = Tỉnh, *_city = Quận, *_district = Phường (address_version 0);
    /// địa chỉ 2 cấp (không quận): address_version 2 với *_state = Tỉnh, *_city = Phường.
    /// </summary>
    internal static Dictionary<string, object?> AddressInfo(
        string prefix, string? name, string? phone, string? detail,
        string? province, string? district, string? ward)
    {
        var w = string.IsNullOrWhiteSpace(ward) ? null : ward.Trim();
        var dist = string.IsNullOrWhiteSpace(district) ? null : district.Trim();
        // Normalizer dùng phường thay quận khi 2 cấp — coi như không có quận.
        if (dist != null && w != null && string.Equals(dist, w, StringComparison.OrdinalIgnoreCase)) dist = null;

        var d = new Dictionary<string, object?> { [$"{prefix}_state"] = province?.Trim() ?? "" };
        if (dist == null)
        {
            d[$"{prefix}_city"] = w ?? "";
            d[$"{prefix}_address_version"] = 2;
        }
        else
        {
            d[$"{prefix}_city"] = dist;
            d[$"{prefix}_district"] = w ?? "";
            d[$"{prefix}_address_version"] = 0;
        }
        if (name != null) d[$"{prefix}_name"] = name;
        if (phone != null) d[$"{prefix}_phone"] = phone;
        if (detail != null) d[$"{prefix}_detail_address"] = detail;
        return d;
    }

    static int ServiceType(PosShippingCarrierSetting s)
    {
        var raw = SpxExtraJson.ReadString(s.ExtraJson, SpxExtraJson.ServiceTypeKey, "service_type");
        return raw?.Trim().ToLowerInvariant() is "2" or "instant" ? 2 : 1;
    }

    /// <summary>1 = SPX đến lấy (mặc định) · 2 = shop gửi tại bưu cục.</summary>
    static int CollectType(PosShippingCarrierSetting s)
    {
        var raw = SpxExtraJson.ReadString(s.ExtraJson, SpxExtraJson.CollectTypeKey, "collect_type");
        return raw?.Trim().ToLowerInvariant() is "2" or "dropoff" or "drop_off" ? 2 : 1;
    }

    /// <summary>Docs: parcel_weight đơn vị KG (VN ≤ 17 kg).</summary>
    internal static double WeightKg(int grams) => Math.Round(Math.Max(10, grams) / 1000.0, 3);

    /// <summary>Docs: VN bắt buộc high_value_processing_collection = 1 khi express_insured_value ≥ 3.000.000.</summary>
    const long HighValueThreshold = 3_000_000;

    Dictionary<string, object?> BuildOrder(
        PosShippingCarrierSetting settings,
        string? orderId,
        string? toName, string? toPhone, string toAddress,
        string? toProvince, string? toDistrict, string? toWard,
        int weightGrams, int lengthCm, int widthCm, int heightCm,
        decimal cod, decimal insurance, string itemName, string? note, bool shopPays)
    {
        var recv = ShippingAddressNormalizer.Normalize(toAddress, toProvince, toDistrict, toWard);
        var inspect = SpxExtraJson.GetBool(settings.ExtraJson, SpxExtraJson.AllowInspectKey);
        var partial = SpxExtraJson.GetBool(settings.ExtraJson, SpxExtraJson.PartialDeliveryKey);
        var useIns = SpxExtraJson.GetBool(settings.ExtraJson, SpxExtraJson.UseInsuranceKey, insurance > 0);
        var insured = useIns ? (long)Math.Max(0, Math.Round(insurance)) : 0;
        var codAmount = (long)Math.Max(0, Math.Round(cod));

        var fulfillment = NoNulls(new Dictionary<string, object?>
        {
            ["payment_role"] = shopPays ? 1 : 2,
            ["cod_collection"] = codAmount > 0 ? 1 : 0,
            ["cod_amount"] = codAmount > 0 ? codAmount : null,
            ["high_value_processing_collection"] = insured >= HighValueThreshold ? 1 : 0,
            ["collect_type"] = CollectType(settings),
            // «Cho xem hàng» = đồng kiểm (allow_mutual_check); giao 1 phần chỉ VN hỗ trợ.
            ["allow_mutual_check"] = inspect ? 1 : 0,
            ["allow_partial_delivery"] = partial ? 1 : 0,
        });

        var deliver = AddressInfo("deliver", toName, toPhone,
            string.IsNullOrWhiteSpace(recv.Address) ? toAddress : recv.Address,
            recv.Province, recv.District, recv.Ward);
        if (!string.IsNullOrWhiteSpace(note))
            deliver["deliver_instruction"] = note.Length > 256 ? note[..256] : note;

        return NoNulls(new Dictionary<string, object?>
        {
            ["order_id"] = string.IsNullOrWhiteSpace(orderId) ? null : (orderId.Length > 32 ? orderId[..32] : orderId),
            ["base_info"] = new Dictionary<string, object?> { ["service_type"] = ServiceType(settings) },
            ["sender_info"] = AddressInfo("sender",
                settings.PickupName ?? "Cửa hàng", settings.PickupPhone ?? "", settings.PickupAddress ?? "",
                settings.FromProvinceName, settings.FromDistrictName, settings.FromWardName),
            ["fulfillment_info"] = fulfillment,
            ["deliver_info"] = deliver,
            ["parcel_info"] = new Dictionary<string, object?>
            {
                ["parcel_weight"] = WeightKg(weightGrams),
                ["parcel_length"] = Math.Max(1, lengthCm),
                ["parcel_width"] = Math.Max(1, widthCm),
                ["parcel_height"] = Math.Max(1, heightCm),
                ["parcel_item_name"] = itemName.Length > 256 ? itemName[..256] : itemName,
                ["parcel_item_quantity"] = 1,
                ["express_insured_value"] = insured,
            },
        });
    }

    /// <summary>JsonIgnoreCondition không áp cho Dictionary — bỏ khóa null để không gửi «"cod_amount": null».</summary>
    static Dictionary<string, object?> NoNulls(Dictionary<string, object?> d)
    {
        foreach (var k in d.Where(kv => kv.Value == null).Select(kv => kv.Key).ToList()) d.Remove(k);
        return d;
    }

    static string MissingCreds() =>
        "Thiếu app-id/app-secret (SPX cấp) hoặc User ID/Secret Key SPX";

    bool HasCreds(PosShippingCarrierSetting s) =>
        !string.IsNullOrWhiteSpace(UserId(s)) && !string.IsNullOrWhiteSpace(Secret(s))
        && !string.IsNullOrWhiteSpace(AppId(s)) && !string.IsNullOrWhiteSpace(AppSecret(s));

    public async Task<ShippingQuoteResult> QuoteAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, CancellationToken ct = default)
    {
        if (!HasCreds(settings))
            return new(false, CarrierCode, 0, Message: MissingCreds());
        if (string.IsNullOrWhiteSpace(settings.FromProvinceName))
            return new(false, CarrierCode, 0, Message: "Thiếu tỉnh/thành lấy hàng SPX");
        if (string.IsNullOrWhiteSpace(request.ToProvince) &&
            string.IsNullOrWhiteSpace(ShippingAddressNormalizer.Normalize(
                request.ToAddress, request.ToProvince, request.ToDistrict, request.ToWard).Province))
            return new(false, CarrierCode, 0, Message: "Thiếu tỉnh/thành nhận hàng");

        var order = BuildOrder(settings, null,
            request.ToName, request.ToPhone, request.ToAddress,
            request.ToProvince, request.ToDistrict, request.ToWard,
            request.WeightGrams, request.LengthCm, request.WidthCm, request.HeightCm,
            request.CodAmount, request.InsuranceValue, "Hàng hóa", null, shopPays: true);
        var payload = Credentials(settings);
        payload["orders"] = new[] { order };

        try
        {
            var (res, raw) = await PostSignedAsync(settings, $"{OpenApiPrefix(settings)}/order/batch_check_order", payload, ct);
            using (res)
            {
                if (LooksLikeHtml(raw) || (int)res.StatusCode is 404 or 405)
                    return new(false, CarrierCode, 0,
                        Message: "SPX chưa mở Open API trên host mặc định. Điền Api Base URL do SPX cấp rồi thử lại.",
                        RawJson: raw.Length > 500 ? raw[..500] : raw);

                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
                var root = doc.RootElement;
                if (!IsOpenApiSuccess(root, out var data))
                    return new(false, CarrierCode, 0, Message: ReadError(root, raw), RawJson: raw);

                var first = FirstOrder(data);
                if (first == null)
                    return new(false, CarrierCode, 0, Message: FirstFail(data) ?? "SPX không trả cước", RawJson: raw);

                var fee = ReadDecimal(first.Value, "estimated_shipping_fee", "basic_shipping_fee") ?? 0;
                return new(fee > 0, CarrierCode, fee,
                    ServiceName: ServiceType(settings) == 2 ? "SPX Instant" : "SPX Express",
                    ServiceCode: ServiceType(settings).ToString(CultureInfo.InvariantCulture),
                    Message: fee > 0 ? null : "SPX trả cước 0",
                    RawJson: raw);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "SPX quote failed");
            return new(false, CarrierCode, 0, Message: ex.Message);
        }
    }

    /// <summary>Docs 1.1: khung giờ lấy hàng sớm nhất (bắt buộc khi collect_type = 1).</summary>
    async Task<(long PickupTime, long RangeId, string? Range, string? Error)> EarliestPickupSlotAsync(
        PosShippingCarrierSetting settings, CancellationToken ct)
    {
        var payload = Credentials(settings);
        payload["service_type"] = ServiceType(settings);
        var (res, raw) = await PostSignedAsync(settings, $"{OpenApiPrefix(settings)}/order/get_pickup_time", payload, ct);
        using (res)
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;
            if (!IsOpenApiSuccess(root, out var data))
                return (0, 0, null, ReadError(root, raw));
            if (data.ValueKind == JsonValueKind.Array)
            {
                foreach (var day in data.EnumerateArray())
                {
                    var t = ReadDecimal(day, "pickup_time");
                    if (t is null or <= 0 || !day.TryGetProperty("slots", out var slots) ||
                        slots.ValueKind != JsonValueKind.Array || slots.GetArrayLength() == 0)
                        continue;
                    var slot = slots[0];
                    var id = ReadDecimal(slot, "pickup_time_range_id") ?? 0;
                    return ((long)t.Value, (long)id, ReadString(slot, "pickup_time_range"), null);
                }
            }
            return (0, 0, null, "SPX không còn khung giờ lấy hàng");
        }
    }

    public async Task<ShippingCreateResult> CreateAsync(
        PosShippingCarrierSetting settings, PosSaleOrder order, ShippingCreateRequest request,
        CancellationToken ct = default)
    {
        if (!HasCreds(settings))
            return new(false, CarrierCode, Message: MissingCreds());

        var toPhone = order.DeliveryPhone ?? "";
        var toAddress = order.DeliveryAddress ?? "";
        if (string.IsNullOrWhiteSpace(toPhone) || string.IsNullOrWhiteSpace(toAddress))
            return new(false, CarrierCode, Message: "Đơn thiếu SĐT / địa chỉ giao");

        var itemNames = order.Lines?
            .Where(l => l.Deleted == null && !string.IsNullOrWhiteSpace(l.ProductName))
            .Select(l => l.ProductName!.Trim())
            .Distinct()
            .Take(5)
            .ToList() ?? [];
        var itemName = itemNames.Count > 0 ? string.Join(", ", itemNames) : $"Đơn {order.OrderNo}";

        var line = BuildOrder(
            settings, order.OrderNo,
            order.CustomerName ?? "Khách", toPhone, toAddress,
            request.ToProvince ?? order.DeliveryProvince,
            request.ToDistrict ?? order.DeliveryDistrict,
            request.ToWard ?? order.DeliveryWard,
            request.WeightGrams, request.LengthCm, request.WidthCm, request.HeightCm,
            request.CodAmount ?? 0,
            order.PayableTotal,
            itemName,
            request.Note ?? order.Note,
            ShippingFeePayer.ShopPaysCarrier(request.ShipFeePayer));

        try
        {
            if (CollectType(settings) == 1)
            {
                var slot = await EarliestPickupSlotAsync(settings, ct);
                if (slot.Error != null)
                    return new(false, CarrierCode, Message: $"Không lấy được khung giờ lấy hàng SPX: {slot.Error}");
                var ful = (Dictionary<string, object?>)line["fulfillment_info"]!;
                ful["pickup_time"] = slot.PickupTime;
                ful["pickup_time_range_id"] = slot.RangeId;
                if (!string.IsNullOrWhiteSpace(slot.Range)) ful["pickup_time_range"] = slot.Range;
            }

            var payload = Credentials(settings);
            payload["orders"] = new[] { line };
            var (res, raw) = await PostSignedAsync(settings, $"{OpenApiPrefix(settings)}/order/batch_create_order", payload, ct);
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

                var first = FirstOrder(data);
                var tracking = first == null ? null : ReadString(first.Value, "tracking_no");
                if (string.IsNullOrWhiteSpace(tracking))
                    return new(false, CarrierCode, Message: FirstFail(data) ?? ReadError(root, raw), RawJson: raw);

                var fee = ReadDecimal(first!.Value, "estimated_shipping_fee", "basic_shipping_fee");
                var link = ReadString(first.Value, "tracking_link") ?? PublicTrackUrl(tracking);
                return new(true, CarrierCode,
                    TrackingCode: tracking, CarrierOrderId: tracking,
                    LabelUrl: link, Fee: fee,
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
        if (!HasCreds(settings))
            return new(false, CarrierCode, Message: MissingCreds());
        var tn = trackingCode.Trim();
        if (tn.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã vận đơn SPX");

        var payload = Credentials(settings);
        payload["tracking_no_list"] = new[] { tn };
        try
        {
            var (res, raw) = await PostSignedAsync(settings, $"{OpenApiPrefix(settings)}/order/batch_cancel_order", payload, ct);
            using (res)
            {
                if (LooksLikeHtml(raw) || (int)res.StatusCode is 404 or 405)
                    return new(false, CarrierCode, Message: "SPX Open API hủy đơn chưa khả dụng trên host hiện tại.");

                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
                var root = doc.RootElement;
                if (!IsOpenApiSuccess(root, out var data))
                    return new(false, CarrierCode, Message: ReadError(root, raw));
                // Docs: mã hủy được nằm trong data.tracking_no_list; mã lỗi ở fail_list (vd 13002 đã lấy hàng).
                var cancelled = data.ValueKind == JsonValueKind.Object
                    && data.TryGetProperty("tracking_no_list", out var ok) && ok.ValueKind == JsonValueKind.Array
                    && ok.EnumerateArray().Any(x => string.Equals(x.GetString(), tn, StringComparison.OrdinalIgnoreCase));
                if (!cancelled)
                    return new(false, CarrierCode, Message: FirstFail(data) ?? "SPX không hủy được vận đơn");
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

        if (HasCreds(settings))
        {
            var payload = Credentials(settings);
            payload["tracking_no_list"] = new[] { tn };
            try
            {
                var (res, raw) = await PostSignedAsync(
                    settings, $"{OpenApiPrefix(settings)}/order/batch_get_shipping_label", payload, ct);
                using (res)
                {
                    if (!LooksLikeHtml(raw) && (int)res.StatusCode is not (404 or 405))
                    {
                        using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
                        var root = doc.RootElement;
                        if (IsOpenApiSuccess(root, out var data))
                        {
                            // Docs: data.awb_link — hiệu lực 30 phút, mở tối đa 10 lần.
                            var url = ReadString(data, "awb_link");
                            if (!string.IsNullOrWhiteSpace(url))
                                return new(true, CarrierCode, LabelUrl: url, Message: "Phiếu gửi SPX (link 30 phút)");
                            var fail = FirstFail(data);
                            if (fail != null) logger.LogWarning("SPX label {Tn}: {Msg}", tn, fail);
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
            Message: "Link tra cứu / phiếu SPX", Format: "link");
    }

    public async Task<ShippingTrackingResult> GetTrackingAsync(
        PosShippingCarrierSetting settings, string trackingCode, CancellationToken ct = default)
    {
        var tn = (trackingCode ?? "").Trim();
        if (tn.Length == 0)
            return new(false, CarrierCode, Message: "Thiếu mã vận đơn SPX");

        if (HasCreds(settings))
        {
            var open = await TryOpenApiTrackingAsync(settings, tn, ct);
            if (open != null) return open;
        }

        return await PublicTrackingAsync(tn, ct);
    }

    async Task<ShippingTrackingResult?> TryOpenApiTrackingAsync(
        PosShippingCarrierSetting settings, string tn, CancellationToken ct)
    {
        var payload = Credentials(settings);
        payload["tracking_no_list"] = new[] { tn };
        try
        {
            var (res, raw) = await PostSignedAsync(settings, $"{OpenApiPrefix(settings)}/order/batch_search_order", payload, ct);
            using (res)
            {
                if (LooksLikeHtml(raw) || (int)res.StatusCode is 404 or 405)
                    return null;
                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
                var root = doc.RootElement;
                if (!IsOpenApiSuccess(root, out var data))
                    return null;
                var first = FirstOrder(data);
                if (first == null)
                    return new(false, CarrierCode, Message: FirstFail(data) ?? "SPX chưa có hành trình cho mã này",
                        RawJson: raw);
                return ParseTrackingPayload(first.Value, raw);
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

    /// <summary>
    /// StatusName = trạng thái gốc của SPX (vd «Delivered») để quy đổi <see cref="ShipmentStatus.FromSpx"/>;
    /// StatusCode = status_code (1001…7001); Message = nhãn tiếng Việt.
    /// </summary>
    ShippingTrackingResult ParseTrackingPayload(JsonElement data, string raw)
    {
        var codeText = ReadString(data, "status_code");
        int? code = int.TryParse(codeText, NumberStyles.Integer, CultureInfo.InvariantCulture, out var c) ? c : null;
        var status = ReadString(data, "status", "current_status", "status_name", "milestone") ?? codeText;
        var events = new List<ShippingTrackingEvent>();
        foreach (var key in new[] { "routes", "tracking_list", "trackings", "events", "checkpoints", "history" })
        {
            if (!data.TryGetProperty(key, out var arr) || arr.ValueKind != JsonValueKind.Array) continue;
            foreach (var ev in arr.EnumerateArray())
            {
                var st = ReadString(ev, "status", "status_name", "milestone", "message", "description");
                int? evCode = int.TryParse(ReadString(ev, "status_code"), out var ec) ? ec : null;
                var loc = ReadString(ev, "location", "hub", "city", "address");
                var note = ReadString(ev, "message", "description");
                var time = ReadString(ev, "ctime", "time", "event_time", "timestamp", "created_at");
                foreach (var tk in new[] { "timestamp", "ctime" })
                {
                    if (ev.TryGetProperty(tk, out var tEl) && tEl.ValueKind == JsonValueKind.Number
                        && tEl.TryGetInt64(out var unix) && unix > 1_000_000)
                    {
                        time = DateTimeOffset.FromUnixTimeSeconds(unix).ToOffset(TimeSpan.FromHours(7))
                            .ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
                        break;
                    }
                }
                events.Add(new ShippingTrackingEvent(evCode, st, time, loc, note));
            }
            break;
        }

        var display = SpxWebhookHelper.StatusLabel(codeText ?? status);
        return new(
            true, CarrierCode,
            StatusCode: code,
            StatusName: status,
            MappedOnlineStatus: SpxWebhookHelper.MapOnlineStatus(codeText ?? status),
            Events: events,
            Message: display,
            RawJson: raw);
    }

    public static string PublicTrackUrl(string tracking) =>
        $"https://spx.vn/track?{Uri.EscapeDataString(tracking)}";
}
