using System.Text;
using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

public class GhtkShippingClient(IHttpClientFactory httpClientFactory, ILogger<GhtkShippingClient> logger)
    : IShippingCarrierClient
{
    public string CarrierCode => ShippingCarrierCodes.Ghtk;

    string BaseUrl(PosShippingCarrierSetting s)
    {
        if (!string.IsNullOrWhiteSpace(s.ApiBaseUrl)) return s.ApiBaseUrl.Trim().TrimEnd('/');
        return s.UseSandbox
            ? "https://services-staging.ghtklab.com"
            : "https://services.giaohangtietkiem.vn";
    }

    HttpClient Client(PosShippingCarrierSetting s)
    {
        var http = httpClientFactory.CreateClient("shipping-ghtk");
        http.DefaultRequestHeaders.Remove("Token");
        http.DefaultRequestHeaders.Remove("X-Client-Source");
        if (!string.IsNullOrWhiteSpace(s.ApiToken))
            http.DefaultRequestHeaders.TryAddWithoutValidation("Token", s.ApiToken.Trim());
        if (!string.IsNullOrWhiteSpace(s.ShopId))
            http.DefaultRequestHeaders.TryAddWithoutValidation("X-Client-Source", s.ShopId.Trim());
        return http;
    }

    public async Task<ShippingQuoteResult> QuoteAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(settings.ApiToken))
            return new(false, CarrierCode, 0, Message: "Thiếu Token GHTK");
        if (string.IsNullOrWhiteSpace(settings.FromProvinceName) ||
            string.IsNullOrWhiteSpace(settings.FromDistrictName))
            return new(false, CarrierCode, 0, Message: "Thiếu tỉnh/quận lấy hàng GHTK");
        if (string.IsNullOrWhiteSpace(request.ToProvince) || string.IsNullOrWhiteSpace(request.ToDistrict))
            return new(false, CarrierCode, 0, Message: "Thiếu tỉnh/quận nhận hàng");

        var qs = new Dictionary<string, string?>
        {
            ["pick_province"] = settings.FromProvinceName,
            ["pick_district"] = settings.FromDistrictName,
            ["province"] = request.ToProvince,
            ["district"] = request.ToDistrict,
            ["address"] = request.ToAddress,
            ["weight"] = Math.Max(0.1, request.WeightGrams / 1000.0).ToString("0.###",
                System.Globalization.CultureInfo.InvariantCulture),
            ["value"] = ((int)Math.Max(0, request.InsuranceValue)).ToString(),
            ["deliver_option"] = "none",
        };
        if (!string.IsNullOrWhiteSpace(settings.FromWardName))
            qs["pick_ward"] = settings.FromWardName;
        if (!string.IsNullOrWhiteSpace(request.ToWard))
            qs["ward"] = request.ToWard;

        try
        {
            var http = Client(settings);
            var url = Query($"{BaseUrl(settings)}/services/shipment/fee", qs);
            using var res = await http.GetAsync(url, ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var ok = root.TryGetProperty("success", out var s) && s.GetBoolean();
            if (!ok)
            {
                var msg = root.TryGetProperty("message", out var m) ? m.GetString() : raw;
                return new(false, CarrierCode, 0, Message: msg, RawJson: raw);
            }
            var fee = 0m;
            if (root.TryGetProperty("fee", out var feeEl))
            {
                if (feeEl.ValueKind == JsonValueKind.Object &&
                    feeEl.TryGetProperty("fee", out var inner))
                    fee = inner.GetDecimal();
                else if (feeEl.ValueKind == JsonValueKind.Number)
                    fee = feeEl.GetDecimal();
            }
            return new(true, CarrierCode, fee, ServiceName: "GHTK", RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHTK quote failed");
            return new(false, CarrierCode, 0, Message: ex.Message);
        }
    }

    public async Task<ShippingCreateResult> CreateAsync(
        PosShippingCarrierSetting settings, PosSaleOrder order, ShippingCreateRequest request,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(settings.ApiToken))
            return new(false, CarrierCode, Message: "Thiếu Token GHTK");

        var products = new[]
        {
            new Dictionary<string, object?>
            {
                ["name"] = $"Đơn {order.OrderNo}",
                ["weight"] = Math.Max(0.1, request.WeightGrams / 1000.0),
                ["quantity"] = 1,
                ["product_code"] = order.OrderNo,
            }
        };

        var orderObj = new Dictionary<string, object?>
        {
            ["id"] = order.OrderNo,
            ["pick_name"] = settings.PickupName ?? "Cửa hàng",
            ["pick_address"] = settings.PickupAddress ?? "",
            ["pick_province"] = settings.FromProvinceName ?? "",
            ["pick_district"] = settings.FromDistrictName ?? "",
            ["pick_ward"] = settings.FromWardName ?? "",
            ["pick_tel"] = settings.PickupPhone ?? "",
            ["tel"] = order.DeliveryPhone ?? "",
            ["name"] = order.CustomerName ?? "Khách",
            ["address"] = order.DeliveryAddress ?? "",
            ["province"] = !string.IsNullOrWhiteSpace(request.ToProvince)
                ? request.ToProvince
                : (order.DeliveryProvince ?? ""),
            ["district"] = !string.IsNullOrWhiteSpace(request.ToDistrict)
                ? request.ToDistrict
                : (order.DeliveryDistrict ?? ""),
            ["ward"] = !string.IsNullOrWhiteSpace(request.ToWard)
                ? request.ToWard
                : (order.DeliveryWard ?? ""),
            ["hamlet"] = "Khác",
            ["is_freeship"] = 1,
            ["pick_money"] = (int)Math.Max(0, request.CodAmount ?? 0),
            ["note"] = request.Note ?? order.Note ?? "",
            ["value"] = (int)Math.Max(0, order.PayableTotal),
            ["transport"] = "road",
        };

        if (string.IsNullOrWhiteSpace(orderObj["province"] as string) ||
            string.IsNullOrWhiteSpace(orderObj["district"] as string))
            return new(false, CarrierCode,
                Message: "GHTK cần Tỉnh + Quận/Huyện trên đơn giao hàng");

        var body = new Dictionary<string, object?>
        {
            ["products"] = products,
            ["order"] = orderObj,
        };

        try
        {
            var http = Client(settings);
            var url = $"{BaseUrl(settings)}/services/shipment/order";
            using var res = await http.PostAsync(url,
                new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"), ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var ok = root.TryGetProperty("success", out var s) && s.GetBoolean();
            if (!ok)
            {
                var msg = root.TryGetProperty("message", out var m) ? m.GetString() : raw;
                return new(false, CarrierCode, Message: msg, RawJson: raw);
            }
            string? tracking = null;
            string? label = null;
            decimal? fee = null;
            if (root.TryGetProperty("order", out var o))
            {
                if (o.TryGetProperty("label", out var l)) tracking = l.GetString();
                if (o.TryGetProperty("tracking_id", out var t) && tracking == null)
                    tracking = t.GetRawText().Trim('"');
                if (o.TryGetProperty("fee", out var f)) fee = f.GetDecimal();
            }
            return new(true, CarrierCode, TrackingCode: tracking, CarrierOrderId: tracking,
                LabelUrl: label, Fee: fee, Message: "Tạo vận đơn GHTK thành công", RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHTK create failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    static string Query(string baseUrl, Dictionary<string, string?> qs)
    {
        var parts = qs.Where(kv => !string.IsNullOrWhiteSpace(kv.Value))
            .Select(kv => $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value!)}");
        return $"{baseUrl}?{string.Join("&", parts)}";
    }
}
