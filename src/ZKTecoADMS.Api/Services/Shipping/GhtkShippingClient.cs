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

        var recv = ShippingAddressNormalizer.Normalize(
            request.ToAddress, request.ToProvince, request.ToDistrict, request.ToWard);
        if (string.IsNullOrWhiteSpace(recv.Province) || string.IsNullOrWhiteSpace(recv.District))
            return new(false, CarrierCode, 0,
                Message: "Thiếu tỉnh/quận nhận hàng (điền Quận hoặc Phường trên đơn)");

        var qs = new Dictionary<string, string?>
        {
            ["pick_province"] = settings.FromProvinceName,
            ["pick_district"] = settings.FromDistrictName,
            ["province"] = recv.Province,
            ["district"] = recv.District,
            ["address"] = string.IsNullOrWhiteSpace(recv.Address) ? request.ToAddress : recv.Address,
            // OpenAPI GHTK: weight đơn vị Gram (integer) — không phải kg.
            ["weight"] = Math.Max(1, request.WeightGrams).ToString(),
            ["value"] = ((int)Math.Max(0, request.InsuranceValue)).ToString(),
            ["deliver_option"] = "none",
        };
        if (!string.IsNullOrWhiteSpace(settings.FromWardName))
            qs["pick_ward"] = settings.FromWardName;
        if (!string.IsNullOrWhiteSpace(recv.Ward))
            qs["ward"] = recv.Ward;
        // Một số bản fee nhận kích thước (cm) — gửi kèm để tính lại theo kiện.
        if (request.LengthCm > 0) qs["length"] = request.LengthCm.ToString();
        if (request.WidthCm > 0) qs["width"] = request.WidthCm.ToString();
        if (request.HeightCm > 0) qs["height"] = request.HeightCm.ToString();

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
            var fee = ParseFee(root);
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

        var weightKg = Math.Max(0.1, request.WeightGrams / 1000.0);
        var products = new List<Dictionary<string, object?>>();
        var activeLines = order.Lines?
            .Where(l => l.Deleted == null)
            .ToList() ?? [];
        if (activeLines.Count > 0)
        {
            var perItemKg = weightKg / activeLines.Count;
            foreach (var line in activeLines.Take(40))
            {
                products.Add(new Dictionary<string, object?>
                {
                    ["name"] = string.IsNullOrWhiteSpace(line.ProductName) ? "Hàng hóa" : line.ProductName,
                    ["weight"] = Math.Max(0.01, perItemKg),
                    ["quantity"] = Math.Max(1, (int)Math.Ceiling(line.Qty)),
                    ["product_code"] = order.OrderNo,
                });
            }
        }
        if (products.Count == 0)
        {
            products.Add(new Dictionary<string, object?>
            {
                ["name"] = $"Đơn {order.OrderNo}",
                ["weight"] = weightKg,
                ["quantity"] = 1,
                ["product_code"] = order.OrderNo,
            });
        }

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
            ["is_freeship"] = ShippingFeePayer.ShopPaysCarrier(request.ShipFeePayer) ? 1 : 0,
            ["pick_money"] = (int)Math.Max(0, request.CodAmount ?? 0),
            ["note"] = request.Note ?? order.Note ?? "",
            ["value"] = (int)Math.Max(0, order.PayableTotal),
            ["transport"] = "road",
        };

        var pickId = GhtkExtraJson.GetPickAddressId(settings.ExtraJson);
        if (!string.IsNullOrWhiteSpace(pickId) && int.TryParse(pickId, out var pickNum))
            orderObj["pick_address_id"] = pickNum;

        if (request.LengthCm > 0) orderObj["total_length"] = request.LengthCm;
        if (request.WidthCm > 0) orderObj["total_width"] = request.WidthCm;
        if (request.HeightCm > 0) orderObj["total_height"] = request.HeightCm;

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
            var url = $"{BaseUrl(settings)}/services/shipment/order/?ver=1.5";
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
            decimal? fee = null;
            if (root.TryGetProperty("order", out var o))
            {
                if (o.TryGetProperty("label", out var l)) tracking = l.GetString();
                if (o.TryGetProperty("tracking_id", out var t) && string.IsNullOrWhiteSpace(tracking))
                    tracking = t.ValueKind == JsonValueKind.String ? t.GetString() : t.GetRawText().Trim('"');
                if (o.TryGetProperty("fee", out var f) && f.ValueKind == JsonValueKind.Number)
                    fee = f.GetDecimal();
            }
            var labelUrl = string.IsNullOrWhiteSpace(tracking)
                ? null
                : $"{BaseUrl(settings)}/services/label/{Uri.EscapeDataString(tracking)}";
            return new(true, CarrierCode, TrackingCode: tracking, CarrierOrderId: tracking,
                LabelUrl: labelUrl, Fee: fee, Message: "Tạo vận đơn GHTK thành công", RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHTK create failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    static decimal ParseFee(JsonElement root)
    {
        if (!root.TryGetProperty("fee", out var feeEl)) return 0;
        if (feeEl.ValueKind == JsonValueKind.Number) return feeEl.GetDecimal();
        if (feeEl.ValueKind != JsonValueKind.Object) return 0;
        // Prefer ship_fee_only + ext, else fee.fee
        if (feeEl.TryGetProperty("fee", out var inner) && inner.ValueKind == JsonValueKind.Number)
            return inner.GetDecimal();
        if (feeEl.TryGetProperty("ship_fee_only", out var only) && only.ValueKind == JsonValueKind.Number)
            return only.GetDecimal();
        return 0;
    }

    static string Query(string baseUrl, Dictionary<string, string?> qs)
    {
        var parts = qs.Where(kv => !string.IsNullOrWhiteSpace(kv.Value))
            .Select(kv => $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value!)}");
        return $"{baseUrl}?{string.Join("&", parts)}";
    }
}
