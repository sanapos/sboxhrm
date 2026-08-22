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
            return "Token không hợp lệ để tạo vận đơn. Token Partner 32 ký tự chỉ tra cước — "
                   + "nhập đúng Mật khẩu Viettel Post (Username đã lưu) rồi Lưu để hệ thống lấy JWT, "
                   + "hoặc dán Token JWT (eyJ...) từ partner.viettelpost.vn.";
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
            using var connReq = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/user/ownerconnect")
            {
                Content = new StringContent(loginBody, Encoding.UTF8, "application/json"),
            };
            connReq.Headers.TryAddWithoutValidation("Token", temp);
            using var connRes = await http.SendAsync(connReq, ct);
            var connRaw = await connRes.Content.ReadAsStringAsync(ct);
            using var connDoc = JsonDocument.Parse(connRaw);
            var connRoot = connDoc.RootElement;
            if (!IsApiError(connRoot))
            {
                var longToken = ParseTokenFromLogin(connRoot);
                if (!string.IsNullOrWhiteSpace(longToken))
                    return (longToken, null);
            }
            else
            {
                var ocErr = ParseApiError(connRoot, connRaw);
                logger.LogWarning("ViettelPost ownerconnect: {Msg} — dùng token tạm", ocErr);
            }
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "ViettelPost ownerconnect skipped");
        }

        return (temp, null);
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

        var (fromLogin, loginErr) = await TryLoginSessionTokenAsync(settings, ct);
        if (!string.IsNullOrWhiteSpace(fromLogin))
            return (fromLogin, null);

        if (IsPartnerPortalToken(settings.ApiToken))
            return (null, MapTokenError("Token invalid", forCreate: true));

        if (!string.IsNullOrWhiteSpace(loginErr))
            return (null, loginErr);

        return (null, "Nhập Username + Mật khẩu Viettel Post hoặc Token JWT (eyJ...) để tạo vận đơn.");
    }

    async Task<string?> EnsureTokenAsync(PosShippingCarrierSetting settings, CancellationToken ct) =>
        await EnsureQuoteTokenAsync(settings, ct);

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
            ["ORDER_PAYMENT"] = (request.CodAmount ?? 0) > 0 ? 3 : 1,
            ["MONEY_COLLECTION"] = (int)Math.Max(0, request.CodAmount ?? 0),
            ["ORDER_SERVICE"] = string.IsNullOrWhiteSpace(request.ServiceCode) ? "VCN" : request.ServiceCode,
            ["ORDER_SERVICE_ADD"] = "",
            ["ORDER_NOTE"] = request.Note ?? "",
            ["CHECK_UNIQUE"] = true,
        };

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

            return new(true, CarrierCode, TrackingCode: tracking, CarrierOrderId: tracking,
                Fee: fee, Message: $"Tạo vận đơn thành công · Mã {tracking}", RawJson: raw);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "ViettelPost create failed");
            return new(false, CarrierCode, Message: ex.Message);
        }
    }
}
