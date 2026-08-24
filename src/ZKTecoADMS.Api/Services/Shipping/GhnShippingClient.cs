using System.Text;
using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

public class GhnShippingClient(IHttpClientFactory httpClientFactory, ILogger<GhnShippingClient> logger)
    : IShippingCarrierClient
{
    public string CarrierCode => ShippingCarrierCodes.Ghn;

    string BaseUrl(PosShippingCarrierSetting s)
    {
        if (!string.IsNullOrWhiteSpace(s.ApiBaseUrl)) return s.ApiBaseUrl.Trim().TrimEnd('/');
        return s.UseSandbox
            ? "https://dev-online-gateway.ghn.vn"
            : "https://online-gateway.ghn.vn";
    }

    HttpClient Client(PosShippingCarrierSetting s)
    {
        var http = httpClientFactory.CreateClient("shipping-ghn");
        http.DefaultRequestHeaders.Remove("Token");
        http.DefaultRequestHeaders.Remove("ShopId");
        if (!string.IsNullOrWhiteSpace(s.ApiToken))
            http.DefaultRequestHeaders.TryAddWithoutValidation("Token", s.ApiToken.Trim());
        if (!string.IsNullOrWhiteSpace(s.ShopId))
            http.DefaultRequestHeaders.TryAddWithoutValidation("ShopId", s.ShopId.Trim());
        return http;
    }

    static bool NameMatch(string? a, string? b)
    {
        if (string.IsNullOrWhiteSpace(a) || string.IsNullOrWhiteSpace(b)) return false;
        static string Norm(string s) => s.Trim().ToLowerInvariant()
            .Replace("thành phố", "", StringComparison.OrdinalIgnoreCase)
            .Replace("tinh", "", StringComparison.OrdinalIgnoreCase)
            .Replace("tỉnh", "", StringComparison.OrdinalIgnoreCase)
            .Replace("quan", "", StringComparison.OrdinalIgnoreCase)
            .Replace("quận", "", StringComparison.OrdinalIgnoreCase)
            .Replace("huyen", "", StringComparison.OrdinalIgnoreCase)
            .Replace("huyện", "", StringComparison.OrdinalIgnoreCase)
            .Replace("thi xa", "", StringComparison.OrdinalIgnoreCase)
            .Replace("thị xã", "", StringComparison.OrdinalIgnoreCase)
            .Replace("phuong", "", StringComparison.OrdinalIgnoreCase)
            .Replace("phường", "", StringComparison.OrdinalIgnoreCase)
            .Replace("xa", "", StringComparison.OrdinalIgnoreCase)
            .Replace("xã", "", StringComparison.OrdinalIgnoreCase)
            .Replace(" ", "");
        var na = Norm(a);
        var nb = Norm(b);
        return na == nb || na.Contains(nb) || nb.Contains(na);
    }

    async Task<int?> ResolveProvinceIdAsync(HttpClient http, string baseUrl, string? provinceName, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(provinceName)) return null;
        if (int.TryParse(provinceName.Trim(), out var id) && id > 0) return id;
        using var res = await http.GetAsync($"{baseUrl}/shiip/public-api/master-data/province", ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(raw);
        if (!doc.RootElement.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Array)
            return null;
        foreach (var p in data.EnumerateArray())
        {
            var name = p.TryGetProperty("ProvinceName", out var n) ? n.GetString() : null;
            if (NameMatch(name, provinceName))
                return p.TryGetProperty("ProvinceID", out var pid) ? pid.GetInt32() : null;
        }
        return null;
    }

    async Task<int?> ResolveDistrictIdAsync(
        HttpClient http, string baseUrl, int provinceId, string? districtName, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(districtName)) return null;
        if (int.TryParse(districtName.Trim(), out var id) && id > 0) return id;
        var body = JsonSerializer.Serialize(new { province_id = provinceId });
        using var res = await http.PostAsync(
            $"{baseUrl}/shiip/public-api/master-data/district",
            new StringContent(body, Encoding.UTF8, "application/json"), ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(raw);
        if (!doc.RootElement.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Array)
            return null;
        foreach (var d in data.EnumerateArray())
        {
            var name = d.TryGetProperty("DistrictName", out var n) ? n.GetString() : null;
            if (NameMatch(name, districtName))
                return d.TryGetProperty("DistrictID", out var did) ? did.GetInt32() : null;
        }
        return null;
    }

    async Task<string?> ResolveWardCodeAsync(
        HttpClient http, string baseUrl, int districtId, string? wardName, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(wardName)) return null;
        if (wardName.Trim().All(char.IsDigit)) return wardName.Trim();
        var body = JsonSerializer.Serialize(new { district_id = districtId });
        using var res = await http.PostAsync(
            $"{baseUrl}/shiip/public-api/master-data/ward",
            new StringContent(body, Encoding.UTF8, "application/json"), ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(raw);
        if (!doc.RootElement.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Array)
            return null;
        foreach (var w in data.EnumerateArray())
        {
            var name = w.TryGetProperty("WardName", out var n) ? n.GetString() : null;
            if (NameMatch(name, wardName))
                return w.TryGetProperty("WardCode", out var wc) ? wc.GetString() : null;
        }
        return null;
    }

    async Task<(int? ToDistrictId, string? ToWardCode, string? Error)> ResolveToAsync(
        PosShippingCarrierSetting settings, string? province, string? district, string? ward,
        CancellationToken ct)
    {
        if (int.TryParse(district, out var directDistrict) && directDistrict > 0)
        {
            string? wardCode = ward;
            if (!string.IsNullOrWhiteSpace(ward) && !ward.Trim().All(char.IsDigit))
            {
                var http0 = Client(settings);
                wardCode = await ResolveWardCodeAsync(http0, BaseUrl(settings), directDistrict, ward, ct)
                           ?? ward;
            }
            return (directDistrict, wardCode, null);
        }

        if (string.IsNullOrWhiteSpace(province) || string.IsNullOrWhiteSpace(district))
        {
            // Đơn vị hành chính 2 cấp: chỉ có phường — tìm quận GHN chứa phường đó.
            if (!string.IsNullOrWhiteSpace(province) && !string.IsNullOrWhiteSpace(ward))
            {
                var found = await FindDistrictByWardAsync(settings, province, ward, ct);
                if (found.DistrictId is > 0)
                    return (found.DistrictId, found.WardCode ?? ward, null);
                return (null, null,
                    found.Error ?? $"GHN không map được phường «{ward}» trong «{province}» (cần quận cũ).");
            }
            return (null, null, "GHN cần Tỉnh + Quận/Huyện (hoặc Phường để tự map).");
        }

        var http = Client(settings);
        var baseUrl = BaseUrl(settings);
        var provinceId = await ResolveProvinceIdAsync(http, baseUrl, province, ct);
        if (provinceId is null or <= 0)
            return (null, null, $"Không tìm thấy tỉnh GHN: {province}");
        var districtId = await ResolveDistrictIdAsync(http, baseUrl, provinceId.Value, district, ct);
        if (districtId is null or <= 0)
        {
            // Quận = tên phường (2 cấp) — thử tìm theo ward trong tỉnh.
            if (!string.IsNullOrWhiteSpace(ward) || !string.IsNullOrWhiteSpace(district))
            {
                var found = await FindDistrictByWardAsync(
                    settings, province, ward ?? district, ct);
                if (found.DistrictId is > 0)
                    return (found.DistrictId, found.WardCode ?? ward, null);
            }
            return (null, null, $"Không tìm thấy quận GHN: {district}");
        }
        var wardCodeResolved = await ResolveWardCodeAsync(http, baseUrl, districtId.Value, ward, ct);
        return (districtId, wardCodeResolved ?? ward, null);
    }

    async Task<(int? DistrictId, string? WardCode, string? Error)> FindDistrictByWardAsync(
        PosShippingCarrierSetting settings, string province, string? wardName, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(wardName))
            return (null, null, "Thiếu phường để map quận GHN");

        var http = Client(settings);
        var baseUrl = BaseUrl(settings);
        var provinceId = await ResolveProvinceIdAsync(http, baseUrl, province, ct);
        if (provinceId is null or <= 0)
            return (null, null, $"Không tìm thấy tỉnh GHN: {province}");

        // Lấy danh sách quận
        var body = JsonSerializer.Serialize(new { province_id = provinceId.Value });
        using var distRes = await http.PostAsync(
            $"{baseUrl}/shiip/public-api/master-data/district",
            new StringContent(body, Encoding.UTF8, "application/json"), ct);
        var distRaw = await distRes.Content.ReadAsStringAsync(ct);
        using var distDoc = JsonDocument.Parse(distRaw);
        if (!distDoc.RootElement.TryGetProperty("data", out var distArr) ||
            distArr.ValueKind != JsonValueKind.Array)
            return (null, null, "GHN không trả danh sách quận");

        foreach (var d in distArr.EnumerateArray())
        {
            var districtId = d.TryGetProperty("DistrictID", out var idEl) ? idEl.GetInt32() : 0;
            if (districtId <= 0) continue;
            // Ưu tiên: tên quận trùng phường (một số khu 2 cấp).
            var distName = d.TryGetProperty("DistrictName", out var dn) ? dn.GetString() : null;
            if (NameMatch(distName, wardName))
            {
                var wc = await ResolveWardCodeAsync(http, baseUrl, districtId, wardName, ct);
                return (districtId, wc ?? wardName, null);
            }
        }

        // Quét ward trong từng quận (giới hạn để tránh quá chậm).
        var scanned = 0;
        foreach (var d in distArr.EnumerateArray())
        {
            if (scanned++ > 40) break;
            var districtId = d.TryGetProperty("DistrictID", out var idEl) ? idEl.GetInt32() : 0;
            if (districtId <= 0) continue;
            var wc = await ResolveWardCodeAsync(http, baseUrl, districtId, wardName, ct);
            if (!string.IsNullOrWhiteSpace(wc))
                return (districtId, wc, null);
        }

        return (null, null, $"Không tìm thấy phường GHN: {wardName}");
    }

    public async Task<ShippingQuoteResult> QuoteAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(settings.ApiToken) || string.IsNullOrWhiteSpace(settings.ShopId))
            return new(false, CarrierCode, 0, Message: "Thiếu Token hoặc ShopId GHN");

        int fromDistrict;
        if (!int.TryParse(settings.FromDistrictId, out fromDistrict) || fromDistrict <= 0)
        {
            // Cấu hình thiếu mã quận — thử resolve từ tên tỉnh/quận/phường lấy hàng.
            if (!string.IsNullOrWhiteSpace(settings.FromProvinceName)
                && (!string.IsNullOrWhiteSpace(settings.FromDistrictName)
                    || !string.IsNullOrWhiteSpace(settings.FromWardName)))
            {
                var (fid, _, ferr) = await ResolveToAsync(
                    settings,
                    settings.FromProvinceName,
                    settings.FromDistrictName,
                    settings.FromWardName,
                    ct);
                if (fid is > 0)
                    fromDistrict = fid.Value;
                else
                    return new(false, CarrierCode, 0,
                        Message: ferr ?? "Thiếu FromDistrictId (mã quận lấy hàng GHN) — cấu hình Cài đặt vận chuyển");
            }
            else
            {
                return new(false, CarrierCode, 0,
                    Message: "Thiếu mã/tên quận lấy hàng GHN trong Cài đặt vận chuyển");
            }
        }

        var recv = ShippingAddressNormalizer.Normalize(
            request.ToAddress, request.ToProvince, request.ToDistrict, request.ToWard);
        var (toDistrict, toWard, err) = await ResolveToAsync(
            settings, recv.Province, recv.District, recv.Ward, ct);
        if (toDistrict is null or <= 0)
            return new(false, CarrierCode, 0, Message: err ?? "Không resolve được quận nhận GHN");

        var body = new Dictionary<string, object?>
        {
            ["from_district_id"] = fromDistrict,
            ["to_district_id"] = toDistrict.Value,
            ["to_ward_code"] = string.IsNullOrWhiteSpace(toWard) ? null : toWard.Trim(),
            ["service_type_id"] = 2,
            ["weight"] = Math.Max(50, request.WeightGrams),
            ["length"] = request.LengthCm,
            ["width"] = request.WidthCm,
            ["height"] = request.HeightCm,
            ["insurance_value"] = (int)Math.Max(0, request.InsuranceValue),
            ["coupon"] = null,
        };
        if (!string.IsNullOrWhiteSpace(settings.FromWardCode))
            body["from_ward_code"] = settings.FromWardCode.Trim();

        try
        {
            var http = Client(settings);
            var url = $"{BaseUrl(settings)}/shiip/public-api/v2/shipping-order/fee";
            using var res = await http.PostAsync(url,
                new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"), ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var code = root.TryGetProperty("code", out var c) ? c.GetInt32() : (int)res.StatusCode;
            if (code != 200)
            {
                var msg = root.TryGetProperty("message", out var m) ? m.GetString() : raw;
                return new(false, CarrierCode, 0, Message: msg, RawJson: raw);
            }
            var data = root.GetProperty("data");
            var total = data.TryGetProperty("total", out var t) ? t.GetDecimal() : 0;
            return new(true, CarrierCode, total, ServiceName: "GHN Express", ServiceCode: "2", RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHN quote failed");
            return new(false, CarrierCode, 0, Message: ex.Message);
        }
    }

    public async Task<ShippingCreateResult> CreateAsync(
        PosShippingCarrierSetting settings, PosSaleOrder order, ShippingCreateRequest request,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(settings.ApiToken) || string.IsNullOrWhiteSpace(settings.ShopId))
            return new(false, CarrierCode, Message: "Thiếu Token hoặc ShopId GHN");

        var toPhone = order.DeliveryPhone ?? "";
        var toAddress = order.DeliveryAddress ?? "";
        if (string.IsNullOrWhiteSpace(toPhone) || string.IsNullOrWhiteSpace(toAddress))
            return new(false, CarrierCode, Message: "Đơn thiếu SĐT / địa chỉ giao");

        var province = request.ToProvince ?? order.DeliveryProvince;
        var district = request.ToDistrict ?? order.DeliveryDistrict;
        var ward = request.ToWard ?? order.DeliveryWard;

        var body = new Dictionary<string, object?>
        {
            ["payment_type_id"] = ShippingFeePayer.ShopPaysCarrier(request.ShipFeePayer) ? 1 : 2,
            ["note"] = request.Note ?? order.Note ?? $"SBOX {order.OrderNo}",
            ["required_note"] = "KHONGCHOXEMHANG",
            ["client_order_code"] = order.OrderNo,
            ["from_name"] = settings.PickupName ?? "Cửa hàng",
            ["from_phone"] = settings.PickupPhone ?? "",
            ["from_address"] = settings.PickupAddress ?? "",
            ["from_ward_name"] = settings.FromWardName ?? "",
            ["from_district_name"] = settings.FromDistrictName ?? "",
            ["from_province_name"] = settings.FromProvinceName ?? "",
            ["to_name"] = order.CustomerName ?? "Khách",
            ["to_phone"] = toPhone,
            ["to_address"] = toAddress,
            ["to_ward_name"] = ward ?? "",
            ["to_district_name"] = district ?? "",
            ["to_province_name"] = province ?? "",
            ["cod_amount"] = (int)Math.Max(0, request.CodAmount ?? 0),
            ["content"] = $"Đơn {order.OrderNo}",
            ["weight"] = Math.Max(50, request.WeightGrams),
            ["length"] = Math.Max(1, request.LengthCm),
            ["width"] = Math.Max(1, request.WidthCm),
            ["height"] = Math.Max(1, request.HeightCm),
            ["insurance_value"] = (int)Math.Min(order.PayableTotal, 5_000_000),
            ["service_type_id"] = int.TryParse(request.ServiceCode, out var st) ? st : 2,
            ["items"] = new[]
            {
                new Dictionary<string, object?>
                {
                    ["name"] = $"Đơn {order.OrderNo}",
                    ["quantity"] = 1,
                    ["weight"] = Math.Max(50, request.WeightGrams),
                }
            },
        };

        if (int.TryParse(settings.FromDistrictId, out var fromDistrict))
            body["from_district_id"] = fromDistrict;
        if (!string.IsNullOrWhiteSpace(settings.FromWardCode))
            body["from_ward_code"] = settings.FromWardCode;

        var (toDistrictId, toWardCode, _) = await ResolveToAsync(settings, province, district, ward, ct);
        if (toDistrictId is > 0)
            body["to_district_id"] = toDistrictId.Value;
        if (!string.IsNullOrWhiteSpace(toWardCode) && toWardCode.All(char.IsDigit))
            body["to_ward_code"] = toWardCode;

        try
        {
            var http = Client(settings);
            var url = $"{BaseUrl(settings)}/shiip/public-api/v2/shipping-order/create";
            using var res = await http.PostAsync(url,
                new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"), ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var code = root.TryGetProperty("code", out var c) ? c.GetInt32() : (int)res.StatusCode;
            if (code != 200)
            {
                var msg = root.TryGetProperty("message", out var m) ? m.GetString() : raw;
                return new(false, CarrierCode, Message: msg, RawJson: raw);
            }
            var data = root.GetProperty("data");
            var tracking = data.TryGetProperty("order_code", out var oc) ? oc.GetString() : null;
            decimal? fee = null;
            if (data.TryGetProperty("total_fee", out var tf)) fee = tf.GetDecimal();
            else if (data.TryGetProperty("fee", out var feeObj) &&
                     feeObj.TryGetProperty("main_service", out var ms))
                fee = ms.GetDecimal();
            return new(true, CarrierCode, TrackingCode: tracking, CarrierOrderId: tracking,
                Fee: fee, Message: "Tạo vận đơn GHN thành công", RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHN create failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }
}
