using System.Text;
using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

public class AhamoveShippingClient(IHttpClientFactory httpClientFactory, ILogger<AhamoveShippingClient> logger)
    : IShippingCarrierClient
{
    public string CarrierCode => ShippingCarrierCodes.Ahamove;

    string BaseUrl(PosShippingCarrierSetting s)
    {
        if (!string.IsNullOrWhiteSpace(s.ApiBaseUrl)) return s.ApiBaseUrl.Trim().TrimEnd('/');
        return s.UseSandbox
            ? "https://partner-apistg.ahamove.com"
            : "https://partner-api.ahamove.com";
    }

    /// <summary>ExtraJson: {"service_id":"SGN-BIKE","lat":10.77,"lng":106.69}</summary>
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

    async Task<(double Lat, double Lng)?> ResolveToCoordsAsync(
        Dictionary<string, JsonElement>? extra,
        ShippingQuoteRequest? quote,
        ShippingCreateRequest? create,
        PosSaleOrder? order,
        CancellationToken ct)
    {
        if (create?.ToLat is > 0 && create.ToLng is > 0)
            return (create.ToLat.Value, create.ToLng.Value);
        if (extra != null &&
            extra.TryGetValue("to_lat", out var tl) &&
            extra.TryGetValue("to_lng", out var tg) &&
            tl.GetDouble() != 0 && tg.GetDouble() != 0)
            return (tl.GetDouble(), tg.GetDouble());

        var address = create != null
            ? (order?.DeliveryAddress ?? "")
            : (quote?.ToAddress ?? "");
        if (string.IsNullOrWhiteSpace(address) && order != null)
        {
            address = string.Join(", ", new[]
            {
                order.DeliveryAddress, order.DeliveryWard, order.DeliveryDistrict, order.DeliveryProvince
            }.Where(x => !string.IsNullOrWhiteSpace(x)));
        }
        else if (quote != null && !string.IsNullOrWhiteSpace(quote.ToAddress))
        {
            address = string.Join(", ", new[]
            {
                quote.ToAddress, quote.ToWard, quote.ToDistrict, quote.ToProvince
            }.Where(x => !string.IsNullOrWhiteSpace(x)));
        }

        return await GeocodeAsync(address, ct);
    }

    public async Task<ShippingQuoteResult> QuoteAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(settings.ApiToken))
            return new(false, CarrierCode, 0, Message: "Thiếu Token AhaMove (api_key)");

        var extra = ParseExtra(settings.ExtraJson);
        var serviceId = "SGN-BIKE";
        if (extra != null && extra.TryGetValue("service_id", out var sid))
            serviceId = sid.GetString() ?? serviceId;

        if (extra == null ||
            !extra.TryGetValue("lat", out var latEl) ||
            !extra.TryGetValue("lng", out var lngEl))
            return new(false, CarrierCode, 0,
                Message: "AhaMove cần lat/lng điểm lấy trong ExtraJson ({\"lat\":..,\"lng\":..,\"service_id\":\"SGN-BIKE\"})");

        var to = await ResolveToCoordsAsync(extra, request, null, null, ct);
        if (to == null)
            return new(false, CarrierCode, 0,
                Message: "Không geocode được địa chỉ nhận. Điền địa chỉ rõ hơn hoặc to_lat/to_lng trong ExtraJson.");

        var path = new[]
        {
            new Dictionary<string, object?>
            {
                ["lat"] = latEl.GetDouble(),
                ["lng"] = lngEl.GetDouble(),
                ["address"] = settings.PickupAddress ?? "",
                ["name"] = settings.PickupName ?? "Shop",
                ["mobile"] = settings.PickupPhone ?? "",
            },
            new Dictionary<string, object?>
            {
                ["lat"] = to.Value.Lat,
                ["lng"] = to.Value.Lng,
                ["address"] = request.ToAddress,
                ["name"] = request.ToName,
                ["mobile"] = request.ToPhone,
                ["cod"] = (int)Math.Max(0, request.CodAmount),
            },
        };

        var qs = new Dictionary<string, string>
        {
            ["token"] = settings.ApiToken.Trim(),
            ["order_time"] = "0",
            ["path"] = JsonSerializer.Serialize(path),
            ["service_id"] = serviceId,
            ["payment_method"] = "BALANCE",
        };

        try
        {
            var http = httpClientFactory.CreateClient("shipping-ahamove");
            var url = Query($"{BaseUrl(settings)}/v3/orders/estimates", qs);
            using var res = await http.GetAsync(url, ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            decimal fee = 0;
            if (root.ValueKind == JsonValueKind.Array && root.GetArrayLength() > 0)
            {
                var first = root[0];
                if (first.TryGetProperty("total_price", out var tp)) fee = tp.GetDecimal();
                else if (first.TryGetProperty("data", out var d) && d.TryGetProperty("total_price", out var tp2))
                    fee = tp2.GetDecimal();
            }
            else if (root.TryGetProperty("total_price", out var tp3))
                fee = tp3.GetDecimal();
            else if (root.TryGetProperty("data", out var data))
            {
                if (data.ValueKind == JsonValueKind.Array && data.GetArrayLength() > 0 &&
                    data[0].TryGetProperty("total_price", out var tp4))
                    fee = tp4.GetDecimal();
                else if (data.TryGetProperty("total_price", out var tp5))
                    fee = tp5.GetDecimal();
            }

            if (fee <= 0 && !res.IsSuccessStatusCode)
            {
                var msg = root.TryGetProperty("description", out var desc) ? desc.GetString()
                    : root.TryGetProperty("title", out var t) ? t.GetString() : raw;
                return new(false, CarrierCode, 0, Message: msg, RawJson: raw);
            }
            return new(true, CarrierCode, fee, ServiceName: serviceId, ServiceCode: serviceId, RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "AhaMove quote failed");
            return new(false, CarrierCode, 0, Message: ex.Message);
        }
    }

    public async Task<ShippingCreateResult> CreateAsync(
        PosShippingCarrierSetting settings, PosSaleOrder order, ShippingCreateRequest request,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(settings.ApiToken))
            return new(false, CarrierCode, Message: "Thiếu Token AhaMove");

        var extra = ParseExtra(settings.ExtraJson);
        var serviceId = request.ServiceCode;
        if (string.IsNullOrWhiteSpace(serviceId) && extra != null &&
            extra.TryGetValue("service_id", out var sid))
            serviceId = sid.GetString();
        serviceId ??= "SGN-BIKE";

        if (extra == null ||
            !extra.TryGetValue("lat", out var latEl) ||
            !extra.TryGetValue("lng", out var lngEl))
            return new(false, CarrierCode,
                Message: "AhaMove cần lat/lng điểm lấy trong ExtraJson cấu hình cửa hàng.");

        var to = await ResolveToCoordsAsync(extra, null, request, order, ct);
        if (to == null)
            return new(false, CarrierCode,
                Message: "Không geocode được địa chỉ giao. Điền địa chỉ rõ hơn hoặc to_lat/to_lng.");

        var path = new[]
        {
            new Dictionary<string, object?>
            {
                ["lat"] = latEl.GetDouble(),
                ["lng"] = lngEl.GetDouble(),
                ["address"] = settings.PickupAddress ?? "",
                ["name"] = settings.PickupName ?? "Shop",
                ["mobile"] = settings.PickupPhone ?? "",
            },
            new Dictionary<string, object?>
            {
                ["lat"] = to.Value.Lat,
                ["lng"] = to.Value.Lng,
                ["address"] = order.DeliveryAddress ?? "",
                ["name"] = order.CustomerName ?? "Khách",
                ["mobile"] = order.DeliveryPhone ?? "",
                ["cod"] = (int)Math.Max(0, request.CodAmount ?? 0),
                ["tracking_number"] = order.OrderNo,
            },
        };

        var body = new Dictionary<string, object?>
        {
            ["order_time"] = 0,
            ["path"] = path,
            ["service_id"] = serviceId,
            ["payment_method"] = "BALANCE",
            ["remarks"] = request.Note ?? order.Note ?? $"SBOX {order.OrderNo}",
        };

        try
        {
            var http = httpClientFactory.CreateClient("shipping-ahamove");
            var url = $"{BaseUrl(settings)}/v3/orders?token={Uri.EscapeDataString(settings.ApiToken.Trim())}";
            using var res = await http.PostAsync(url,
                new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"), ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;

            string? orderId = null;
            decimal? fee = null;
            if (root.TryGetProperty("order_id", out var oid)) orderId = oid.GetString();
            else if (root.TryGetProperty("data", out var data) && data.TryGetProperty("order_id", out var oid2))
                orderId = oid2.GetString();
            if (root.TryGetProperty("total_price", out var tp)) fee = tp.GetDecimal();
            else if (root.TryGetProperty("data", out var d2) && d2.TryGetProperty("total_price", out var tp2))
                fee = tp2.GetDecimal();

            if (string.IsNullOrWhiteSpace(orderId))
            {
                var msg = root.TryGetProperty("description", out var desc) ? desc.GetString()
                    : root.TryGetProperty("title", out var t) ? t.GetString() : raw;
                return new(false, CarrierCode, Message: msg, RawJson: raw);
            }
            return new(true, CarrierCode, TrackingCode: orderId, CarrierOrderId: orderId,
                Fee: fee, Message: "Tạo đơn AhaMove thành công", RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "AhaMove create failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    static string Query(string baseUrl, Dictionary<string, string> qs)
    {
        var parts = qs.Select(kv => $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}");
        return $"{baseUrl}?{string.Join("&", parts)}";
    }
}
