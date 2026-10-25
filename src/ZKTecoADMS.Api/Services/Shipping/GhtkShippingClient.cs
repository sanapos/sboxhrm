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

    public Task<ShippingQuoteResult> QuoteAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, CancellationToken ct = default) =>
        QuoteTransportAsync(settings, request, "road", ct);

    /// <summary>Hai gói GHTK: đường bộ (tiết kiệm) và đường bay (nhanh, liên tỉnh).</summary>
    public async Task<IReadOnlyList<ShippingQuoteResult>> QuoteOptionsAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, CancellationToken ct = default)
    {
        var road = await QuoteTransportAsync(settings, request, "road", ct);
        var fly = await QuoteTransportAsync(settings, request, "fly", ct);
        var list = new List<ShippingQuoteResult> { road };
        // Nội tỉnh GHTK thường không có đường bay (trả lỗi / cùng giá) — chỉ hiện khi hợp lệ và khác giá.
        if (fly.Success && fly.Fee > 0 && fly.Fee != road.Fee) list.Add(fly);
        return list;
    }

    async Task<ShippingQuoteResult> QuoteTransportAsync(
        PosShippingCarrierSetting settings, ShippingQuoteRequest request, string transport, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(settings.ApiToken))
            return new(false, CarrierCode, 0, Message: "Thiếu Token GHTK");
        // Docs GHTK (api.ghtk.vn/docs, bản 2025): *_district không bắt buộc, *_ward bắt buộc —
        // địa chỉ 2 cấp (Tỉnh + Phường) hợp lệ.
        if (string.IsNullOrWhiteSpace(settings.FromProvinceName) ||
            (string.IsNullOrWhiteSpace(settings.FromDistrictName) && string.IsNullOrWhiteSpace(settings.FromWardName)))
            return new(false, CarrierCode, 0, Message: "Thiếu tỉnh + quận/phường lấy hàng GHTK");

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
            // Normalizer lấy phường thay quận khi địa chỉ 2 cấp — GHTK nhận phường ở «ward», không gửi trùng vào «district».
            ["district"] = RealDistrict(recv),
            ["address"] = string.IsNullOrWhiteSpace(recv.Address) ? request.ToAddress : recv.Address,
            // OpenAPI GHTK: weight đơn vị Gram (integer) — không phải kg.
            ["weight"] = Math.Max(1, request.WeightGrams).ToString(),
            ["value"] = ((int)Math.Max(0, request.InsuranceValue)).ToString(),
            ["deliver_option"] = "none",
            ["transport"] = transport,
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
            // fee.delivery=false: tuyến không hỗ trợ gói này.
            if (root.TryGetProperty("fee", out var feeObj) && feeObj.ValueKind == JsonValueKind.Object
                && feeObj.TryGetProperty("delivery", out var dv) && dv.ValueKind == JsonValueKind.False)
                return new(false, CarrierCode, 0, ServiceName: GhtkServiceName(transport),
                    Message: "GHTK không hỗ trợ tuyến này", RawJson: raw);
            return new(true, CarrierCode, fee, ServiceName: GhtkServiceName(transport),
                ServiceCode: transport, RawJson: raw);
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
            // Docs: note tối đa 120 ký tự.
            ["note"] = Truncate(request.Note ?? order.Note ?? "", 120),
            ["value"] = (int)Math.Max(0, order.PayableTotal),
            ["transport"] = request.ServiceCode is "fly" ? "fly" : "road",
        };

        var pickId = GhtkExtraJson.GetPickAddressId(settings.ExtraJson);
        if (!string.IsNullOrWhiteSpace(pickId) && int.TryParse(pickId, out var pickNum))
            orderObj["pick_address_id"] = pickNum;

        // Docs (pro-docs.ghtk.vn/3-shipping_api): order.length / order.width / order.height (cm).
        if (request.LengthCm > 0) orderObj["length"] = request.LengthCm;
        if (request.WidthCm > 0) orderObj["width"] = request.WidthCm;
        if (request.HeightCm > 0) orderObj["height"] = request.HeightCm;

        // Địa chỉ 2 cấp: Tỉnh + Phường là đủ (district không bắt buộc theo docs 2025).
        if (string.IsNullOrWhiteSpace(orderObj["province"] as string) ||
            (string.IsNullOrWhiteSpace(orderObj["district"] as string)
             && string.IsNullOrWhiteSpace(orderObj["ward"] as string)))
            return new(false, CarrierCode,
                Message: "GHTK cần Tỉnh + Quận/Huyện hoặc Phường/Xã trên đơn giao hàng");

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
                // Docs: order.id đã tồn tại → GHTK trả error.ghtk_label của đơn cũ (gửi lại sau timeout).
                // Nhận lại vận đơn đó thay vì báo lỗi — trừ khi đơn cũ đã hủy (-1).
                if (root.TryGetProperty("error", out var er) && er.ValueKind == JsonValueKind.Object
                    && er.TryGetProperty("code", out var ec) && ec.GetString() == "ORDER_ID_EXIST"
                    && er.TryGetProperty("ghtk_label", out var gl) && !string.IsNullOrWhiteSpace(gl.GetString())
                    && !(er.TryGetProperty("status", out var es) && es.ToString().Trim('"') == "-1"))
                {
                    var existing = gl.GetString()!.Trim();
                    return new(true, CarrierCode, TrackingCode: existing, CarrierOrderId: existing,
                        LabelUrl: $"{BaseUrl(settings)}/services/label/{Uri.EscapeDataString(existing)}",
                        Message: "Đơn đã có trên GHTK — dùng lại vận đơn cũ", RawJson: raw);
                }
                return new(false, CarrierCode, Message: msg, RawJson: raw);
            }
            string? tracking = null;
            decimal? fee = null;
            if (root.TryGetProperty("order", out var o))
            {
                if (o.TryGetProperty("label", out var l)) tracking = l.GetString();
                if (o.TryGetProperty("tracking_id", out var t) && string.IsNullOrWhiteSpace(tracking))
                    tracking = t.ValueKind == JsonValueKind.String ? t.GetString() : t.GetRawText().Trim('"');
                // Docs: order.fee trả dạng chuỗi ("30400") — đọc cả số lẫn chuỗi.
                if (o.TryGetProperty("fee", out var f))
                {
                    if (f.ValueKind == JsonValueKind.Number) fee = f.GetDecimal();
                    else if (f.ValueKind == JsonValueKind.String &&
                             decimal.TryParse(f.GetString(), System.Globalization.NumberStyles.Number,
                                 System.Globalization.CultureInfo.InvariantCulture, out var fs))
                        fee = fs;
                }
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

    static string GhtkServiceName(string transport) =>
        transport == "fly" ? "GHTK Đường bay (nhanh)" : "GHTK Đường bộ (tiết kiệm)";

    // ── Hủy / hành trình / nhãn ─────────────────────────────────────

    public async Task<ShippingCancelResult> CancelOrderAsync(
        PosShippingCarrierSetting settings, string label, CancellationToken ct = default)
    {
        try
        {
            var http = Client(settings);
            using var res = await http.PostAsync(
                $"{BaseUrl(settings)}/services/shipment/cancel/{Uri.EscapeDataString(label)}",
                new StringContent("", Encoding.UTF8, "application/json"), ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;
            var ok = root.TryGetProperty("success", out var s) && s.ValueKind == JsonValueKind.True;
            var msg = root.TryGetProperty("message", out var m) ? m.GetString() : null;
            return new(ok, CarrierCode, ok ? (msg ?? "Đã hủy vận đơn GHTK") : (msg ?? raw));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHTK cancel failed");
            return new(false, CarrierCode, ex.Message);
        }
    }

    public async Task<ShippingTrackingResult> GetTrackingAsync(
        PosShippingCarrierSetting settings, string label, CancellationToken ct = default)
    {
        try
        {
            var http = Client(settings);
            using var res = await http.GetAsync(
                $"{BaseUrl(settings)}/services/shipment/v2/{Uri.EscapeDataString(label)}", ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var ok = root.TryGetProperty("success", out var s) && s.ValueKind == JsonValueKind.True;
            if (!ok || !root.TryGetProperty("order", out var order))
            {
                var msg = root.TryGetProperty("message", out var m) ? m.GetString() : raw;
                return new(false, CarrierCode, Message: msg, RawJson: raw);
            }
            int? statusId = null;
            if (order.TryGetProperty("status", out var st))
            {
                if (st.ValueKind == JsonValueKind.Number && st.TryGetInt32(out var n)) statusId = n;
                else if (st.ValueKind == JsonValueKind.String && int.TryParse(st.GetString(), out var ns)) statusId = ns;
            }
            var text = order.TryGetProperty("status_text", out var tx) ? tx.GetString() : null;
            return new(true, CarrierCode, StatusCode: statusId,
                StatusName: text ?? GhtkWebhookHelper.StatusLabel(statusId), RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHTK tracking failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }

    /// <summary>Tải nhãn PDF (cần Token — máy bán mở qua link ký của SBOX).</summary>
    public async Task<(byte[]? Pdf, string? Error)> DownloadLabelAsync(
        PosShippingCarrierSetting settings, string label, CancellationToken ct = default)
    {
        try
        {
            var http = Client(settings);
            using var res = await http.GetAsync(
                $"{BaseUrl(settings)}/services/label/{Uri.EscapeDataString(label)}?original=portrait&page_size=A6", ct);
            var bytes = await res.Content.ReadAsByteArrayAsync(ct);
            var isPdf = bytes.Length > 4 && bytes[0] == '%' && bytes[1] == 'P' && bytes[2] == 'D' && bytes[3] == 'F';
            if (!res.IsSuccessStatusCode || !isPdf)
                return (null, Encoding.UTF8.GetString(bytes.Take(300).ToArray()));
            return (bytes, null);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHTK label failed");
            return (null, ex.Message);
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

    /// <summary>Quận thật trên đơn — null khi normalizer chỉ lấy phường thay quận (địa chỉ 2 cấp).</summary>
    internal static string? RealDistrict(ShippingAddressNormalizer.ReceiverParts recv) =>
        !string.IsNullOrWhiteSpace(recv.Ward)
        && string.Equals(recv.District, recv.Ward, StringComparison.OrdinalIgnoreCase)
            ? null
            : recv.District;

    static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];

    static string Query(string baseUrl, Dictionary<string, string?> qs)
    {
        var parts = qs.Where(kv => !string.IsNullOrWhiteSpace(kv.Value))
            .Select(kv => $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value!)}");
        return $"{baseUrl}?{string.Join("&", parts)}";
    }
}
