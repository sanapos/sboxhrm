using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Services.Shipping;

internal static class ViettelPostWebhookHelper
{
    /// <summary>Map mã ORDER_STATUS VTP → trạng thái đơn QR online (DeliveryStatus).</summary>
    public static string? MapOnlineStatus(int? statusCode) => statusCode switch
    {
        501 or 504 => QrOnlineOrderStatuses.Delivered,
        503 or 201 or 107 or -15 => QrOnlineOrderStatuses.Cancelled,
        >= 100 => QrOnlineOrderStatuses.Shipping,
        _ => null,
    };
}

internal static class AhamoveWebhookHelper
{
    public static string Normalize(string? status)
    {
        var s = (status ?? "").Trim().ToUpperInvariant().Replace('_', ' ');
        if (s is "IN PROCESS" or "INPROCESS") return "IN PROCESS";
        return s;
    }

    /// <summary>
    /// Trạng thái thật của đơn: AhaMove giữ status = COMPLETED cả khi giao thất bại — thất bại nằm ở
    /// path[i].status = FAILED (i &gt; 0) và sub_status = IN_RETURN (đang hoàn) / RETURNED (đã hoàn về shop).
    /// </summary>
    public static string? EffectiveStatus(System.Text.Json.JsonElement root)
    {
        static string? Str(System.Text.Json.JsonElement e, string key) =>
            e.ValueKind == System.Text.Json.JsonValueKind.Object && e.TryGetProperty(key, out var v)
            && v.ValueKind == System.Text.Json.JsonValueKind.String ? v.GetString() : null;

        var status = Str(root, "status");
        if (Normalize(status) != "COMPLETED") return status;
        var sub = Normalize(Str(root, "sub_status"));
        if (sub == "RETURNED") return "RETURNED";
        if (sub == "IN RETURN") return "IN RETURN";
        if (root.TryGetProperty("path", out var path) && path.ValueKind == System.Text.Json.JsonValueKind.Array)
        {
            var i = 0;
            foreach (var stop in path.EnumerateArray())
                if (i++ > 0 && Normalize(Str(stop, "status")) == "FAILED")
                    return "FAILED";
        }
        return status;
    }

    /// <summary>Đơn nhiều điểm giao: AhaMove gửi mã điểm «24ABCD-1» — mã đơn gốc là phần trước «-số».</summary>
    public static string? BaseOrderId(string? id)
    {
        var s = (id ?? "").Trim();
        var dash = s.LastIndexOf('-');
        return dash > 0 && dash < s.Length - 1 && s[(dash + 1)..].All(char.IsDigit) ? s[..dash] : null;
    }

    public static string? MapOnlineStatus(string? status) => Normalize(status) switch
    {
        "COMPLETED" => QrOnlineOrderStatuses.Delivered,
        "CANCELLED" or "FAILED" or "RETURNED" or "IN RETURN" => QrOnlineOrderStatuses.Cancelled,
        "IDLE" or "ASSIGNING" or "ACCEPTED" or "CONFIRMING" or "IN PROCESS"
            or "PICKING" or "BOARDING" => QrOnlineOrderStatuses.Shipping,
        _ => string.IsNullOrWhiteSpace(status) ? null : QrOnlineOrderStatuses.Shipping,
    };

    public static string DisplayName(string? status) => Normalize(status) switch
    {
        "IDLE" => "Chờ xử lý",
        "ASSIGNING" => "Đang tìm tài xế",
        "ACCEPTED" => "Tài xế đã nhận",
        "CONFIRMING" => "Đang xác nhận",
        "IN PROCESS" => "Đang giao",
        "PICKING" => "Đang lấy hàng",
        "BOARDING" => "Tài xế đang đến",
        "COMPLETED" => "Đã giao",
        "CANCELLED" => "Đã hủy",
        "FAILED" => "Giao thất bại",
        "IN RETURN" => "Đang hoàn hàng về shop",
        "RETURNED" => "Đã hoàn hàng về shop",
        _ => string.IsNullOrWhiteSpace(status) ? "AhaMove" : status.Trim(),
    };
}

public record ShippingCarrierSettingDto(
    string CarrierCode,
    string DisplayName,
    bool Enabled,
    bool UseSandbox,
    bool HasApiToken,
    bool HasPassword,
    /// <summary>Partner · ****41B2 hoặc JWT · ****xYz9 — không trả token đầy đủ.</summary>
    string? ApiTokenHint,
    /// <summary>Partner | Jwt | None</summary>
    string? ApiTokenKind,
    /// <summary>Thông báo sau lưu (vd. JWT đã cập nhật / sai mật khẩu).</summary>
    string? Notice,
    string? ShopId,
    string? Username,
    string? ApiBaseUrl,
    string? PickupName,
    string? PickupPhone,
    string? PickupAddress,
    string? FromProvinceName,
    string? FromDistrictName,
    string? FromWardName,
    string? FromDistrictId,
    string? FromWardCode,
    string? FromProvinceId,
    string? ExtraJson,
    /// <summary>Link webhook (kèm mã bí mật) để dán vào trang quản lý của hãng.</summary>
    string? WebhookUrl = null,
    /// <summary>Mã bí mật webhook (Viettel Post dùng làm Token header).</summary>
    string? WebhookSecret = null);

public record ShippingCarrierSettingUpsertRequest(
    string CarrierCode,
    bool Enabled,
    bool UseSandbox,
    string? ApiToken,
    string? ShopId,
    string? Username,
    string? Password,
    string? ApiBaseUrl,
    string? PickupName,
    string? PickupPhone,
    string? PickupAddress,
    string? FromProvinceName,
    string? FromDistrictName,
    string? FromWardName,
    string? FromDistrictId,
    string? FromWardCode,
    string? FromProvinceId,
    string? ExtraJson);

public partial class PosShippingService(
    ZKTecoDbContext db,
    IEnumerable<IShippingCarrierClient> carriers,
    ILogger<PosShippingService> logger)
{
    IShippingCarrierClient? Resolve(string code) =>
        carriers.FirstOrDefault(c =>
            c.CarrierCode.Equals(ShippingCarrierCodes.Normalize(code), StringComparison.OrdinalIgnoreCase));

    public async Task<List<ShippingCarrierSettingDto>> ListSettingsAsync(Guid storeId, CancellationToken ct)
    {
        // Webhook bắt buộc mã bí mật — sinh sẵn cho hãng đang bật để chủ shop dán link.
        var enabledCodes = await db.PosShippingCarrierSettings.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Enabled)
            .Select(x => x.CarrierCode)
            .ToListAsync(ct);
        foreach (var c in enabledCodes)
            await EnsureWebhookSecretAsync(storeId, c, ct);

        var rows = await db.PosShippingCarrierSettings.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .ToListAsync(ct);
        var map = rows.ToDictionary(r => r.CarrierCode, StringComparer.OrdinalIgnoreCase);
        return ShippingCarrierCodes.All.Select(code =>
        {
            if (map.TryGetValue(code, out var row))
                return ToDto(row);
            return new ShippingCarrierSettingDto(
                code, ShippingCarrierCodes.DisplayName(code),
                false, false, false, false, null, null, null,
                null, null, null, null, null, null,
                null, null, null, null, null, null, null);
        }).ToList();
    }

    static (string? Hint, string? Kind) DescribeToken(string? apiToken)
    {
        var t = (apiToken ?? "").Trim();
        if (t.Length == 0) return (null, "None");
        var kind = t.Contains('.') && t.Length >= 40 ? "Jwt" : "Partner";
        var hint = t.Length <= 4 ? "****" : $"{kind} · ****{t[^4..]}";
        return (hint, kind);
    }

    static ShippingCarrierSettingDto ToDto(PosShippingCarrierSetting s, string? notice = null)
    {
        var (hint, kind) = DescribeToken(s.ApiToken);
        return new(
        s.CarrierCode,
        ShippingCarrierCodes.DisplayName(s.CarrierCode),
        s.Enabled,
        s.UseSandbox,
        !string.IsNullOrWhiteSpace(s.ApiToken),
        !string.IsNullOrWhiteSpace(s.Password),
        hint,
        kind,
        notice,
        s.ShopId,
        s.Username,
        s.ApiBaseUrl,
        s.PickupName,
        s.PickupPhone,
        s.PickupAddress,
        s.FromProvinceName,
        s.FromDistrictName,
        s.FromWardName,
        s.FromDistrictId,
        s.FromWardCode,
        s.FromProvinceId,
        s.ExtraJson,
        WebhookSecret: ViettelPostExtraJson.GetWebhookSecret(s.ExtraJson));
    }

    /// <summary>Sau lưu Viettel Post — LoginVTP (token bí mật) hoặc login → JWT.</summary>
    async Task<string?> TryRefreshViettelJwtAsync(PosShippingCarrierSetting row, CancellationToken ct)
    {
        if (!string.Equals(row.CarrierCode, ShippingCarrierCodes.ViettelPost, StringComparison.OrdinalIgnoreCase))
            return null;

        var client = Resolve(ShippingCarrierCodes.ViettelPost) as ViettelPostShippingClient;
        if (client == null) return null;

        var t = (row.ApiToken ?? "").Trim();
        if (t.Contains('.') && t.Length >= 40)
            return null;

        if (t.Length > 0 && t.Length <= 36)
        {
            var (jwt, err) = await client.TryLoginVtpTokenAsync(row, ct: ct);
            if (!string.IsNullOrWhiteSpace(jwt))
            {
                row.ApiToken = jwt;
                row.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync(ct);
                logger.LogInformation("ViettelPost LoginVTP → JWT for store {StoreId}", row.StoreId);
                return "Đã đổi token bí mật → JWT (LoginVTP) — có thể tạo vận đơn.";
            }
            if (string.IsNullOrWhiteSpace(row.Password))
                return err;
        }

        if (string.IsNullOrWhiteSpace(row.Username) || string.IsNullOrWhiteSpace(row.Password))
            return null;

        var (fromLogin, loginErr) = await client.TryLoginSessionTokenAsync(row, ct);
        if (!string.IsNullOrWhiteSpace(fromLogin))
        {
            row.ApiToken = fromLogin;
            row.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
            logger.LogInformation("ViettelPost JWT refreshed for store {StoreId}", row.StoreId);
            return "Đã lấy JWT Viettel Post — có thể tạo vận đơn.";
        }
        return loginErr ?? "Không lấy được JWT Viettel Post — kiểm tra Username/Mật khẩu.";
    }

    async Task<string?> TryRefreshAhamoveTokenAsync(PosShippingCarrierSetting row, CancellationToken ct)
    {
        if (Resolve(ShippingCarrierCodes.Ahamove) is not AhamoveShippingClient client)
            return null;
        var (ok, err) = await client.EnsureUserTokenAsync(row, ct);
        if (!ok)
            return err ?? "Không lấy được token AhaMove — kiểm tra API Key, SĐT và Sandbox.";
        await db.SaveChangesAsync(ct);
        var env = row.UseSandbox ? "staging" : "production";
        return $"Đã lấy token user AhaMove ({env}) — có thể báo giá / tạo đơn.";
    }

    async Task<PosShippingCarrierSetting?> LoadEnabledCarrierAsync(
        Guid storeId, string code, CancellationToken ct)
    {
        var settings = await db.PosShippingCarrierSettings
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.CarrierCode == code
                                      && x.Deleted == null && x.Enabled, ct);
        if (settings == null) return null;
        if (Resolve(code) is AhamoveShippingClient aha)
        {
            var (ok, _) = await aha.EnsureUserTokenAsync(settings, ct);
            if (ok) await db.SaveChangesAsync(ct);
        }
        return settings;
    }

    public async Task<ShippingCarrierSettingDto> UpsertAsync(
        Guid storeId, ShippingCarrierSettingUpsertRequest req, string? userEmail, CancellationToken ct)
    {
        var code = ShippingCarrierCodes.Normalize(req.CarrierCode);
        if (!ShippingCarrierCodes.All.Contains(code, StringComparer.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Carrier không hỗ trợ: {req.CarrierCode}");

        var row = await db.PosShippingCarrierSettings
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.CarrierCode == code && x.Deleted == null, ct);
        if (row == null)
        {
            row = new PosShippingCarrierSetting
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CarrierCode = code,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = userEmail,
            };
            db.PosShippingCarrierSettings.Add(row);
        }

        row.Enabled = req.Enabled;
        row.UseSandbox = req.UseSandbox;
        if (!string.IsNullOrWhiteSpace(req.ApiToken))
            row.ApiToken = req.ApiToken.Trim();
        if (req.ShopId != null) row.ShopId = NullIfEmpty(req.ShopId);
        if (req.Username != null) row.Username = NullIfEmpty(req.Username);
        if (!string.IsNullOrWhiteSpace(req.Password))
            row.Password = req.Password;
        if (req.ApiBaseUrl != null) row.ApiBaseUrl = NullIfEmpty(req.ApiBaseUrl);
        if (req.PickupName != null) row.PickupName = NullIfEmpty(req.PickupName);
        if (req.PickupPhone != null) row.PickupPhone = NullIfEmpty(req.PickupPhone);
        if (req.PickupAddress != null) row.PickupAddress = NullIfEmpty(req.PickupAddress);
        if (req.FromProvinceName != null) row.FromProvinceName = NullIfEmpty(req.FromProvinceName);
        if (req.FromDistrictName != null) row.FromDistrictName = NullIfEmpty(req.FromDistrictName);
        if (req.FromWardName != null) row.FromWardName = NullIfEmpty(req.FromWardName);
        if (req.FromDistrictId != null) row.FromDistrictId = NullIfEmpty(req.FromDistrictId);
        if (req.FromWardCode != null) row.FromWardCode = NullIfEmpty(req.FromWardCode);
        if (req.FromProvinceId != null) row.FromProvinceId = NullIfEmpty(req.FromProvinceId);
        if (req.ExtraJson != null) row.ExtraJson = NullIfEmpty(req.ExtraJson);
        row.UpdatedAt = DateTime.UtcNow;
        row.UpdatedBy = userEmail;
        await db.SaveChangesAsync(ct);
        string? notice = null;
        if (string.Equals(code, ShippingCarrierCodes.ViettelPost, StringComparison.OrdinalIgnoreCase))
            notice = await TryRefreshViettelJwtAsync(row, ct);
        else if (string.Equals(code, ShippingCarrierCodes.Ahamove, StringComparison.OrdinalIgnoreCase))
            notice = await TryRefreshAhamoveTokenAsync(row, ct);
        return ToDto(row, notice);
    }

    static string? NullIfEmpty(string? v) =>
        string.IsNullOrWhiteSpace(v) ? null : v.Trim();

    public async Task<ShippingQuoteResult> QuoteAsync(
        Guid storeId, ShippingQuoteRequest request, CancellationToken ct)
    {
        var code = ShippingCarrierCodes.Normalize(request.CarrierCode);
        var settings = await LoadEnabledCarrierAsync(storeId, code, ct);
        if (settings == null)
            return new(false, code, 0, Message: $"Chưa bật / cấu hình {ShippingCarrierCodes.DisplayName(code)}");
        var client = Resolve(code);
        if (client == null)
            return new(false, code, 0, Message: "Adapter chưa đăng ký");
        var result = await client.QuoteAsync(settings, request with { CarrierCode = code }, ct);
        if (string.Equals(code, ShippingCarrierCodes.Ahamove, StringComparison.OrdinalIgnoreCase))
            await db.SaveChangesAsync(ct);
        return result;
    }

    public async Task<ShippingPackageEstimate> EstimatePackageForOrderAsync(
        Guid storeId, Guid orderId,
        int? weightGrams, int? lengthCm, int? widthCm, int? heightCm,
        CancellationToken ct)
    {
        var order = await db.PosSaleOrders.AsNoTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == orderId && o.StoreId == storeId && o.Deleted == null, ct);
        if (order == null)
            return ShippingPackageEstimator.FromOverrides(weightGrams, lengthCm, widthCm, heightCm, "missing-order");

        var productIds = order.Lines.Where(l => l.Deleted == null).Select(l => l.ProductId).Distinct().ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && productIds.Contains(p.Id) && p.Deleted == null)
            .ToDictionaryAsync(p => p.Id, ct);
        return ShippingPackageEstimator.FromOrderLines(
            order.Lines, products, weightGrams, lengthCm, widthCm, heightCm);
    }

    public async Task<ShippingCompareResult> CompareForOrderAsync(
        Guid storeId, ShippingCompareRequest request, CancellationToken ct)
    {
        var order = await db.PosSaleOrders.AsNoTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == request.OrderId && o.StoreId == storeId && o.Deleted == null, ct);
        if (order == null)
            throw new InvalidOperationException("Không tìm thấy đơn hàng");
        if (!order.IsDelivery)
            throw new InvalidOperationException("Đơn không phải đơn giao hàng");

        var package = await EstimatePackageForOrderAsync(
            storeId, order.Id, request.WeightGrams, request.LengthCm, request.WidthCm, request.HeightCm, ct);

        var cod = request.CodAmount
                  ?? (order.Status == PosSaleOrderStatus.Completed ? 0m : order.PayableTotal);
        var insurance = Math.Max(0, order.PayableTotal);
        var recv = ShippingAddressNormalizer.FromOrder(order);

        // Nạp cấu hình tuần tự (DbContext không chạy song song) rồi gọi hãng song song.
        var settingsList = await db.PosShippingCarrierSettings
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Enabled)
            .ToListAsync(ct);
        foreach (var st in settingsList)
        {
            if (Resolve(st.CarrierCode) is AhamoveShippingClient aha)
                await aha.EnsureUserTokenAsync(st, ct);
        }

        var quoteReq = new ShippingQuoteRequest(
            "",
            order.CustomerName ?? "Khách",
            order.DeliveryPhone ?? "",
            string.IsNullOrWhiteSpace(recv.Address) ? (order.DeliveryAddress ?? "") : recv.Address,
            recv.Province,
            recv.District,
            recv.Ward,
            WeightGrams: package.ChargeableWeightGrams,
            CodAmount: Math.Max(0, cod),
            InsuranceValue: insurance,
            LengthCm: package.LengthCm,
            WidthCm: package.WidthCm,
            HeightCm: package.HeightCm);

        var tasks = settingsList.Select(async st =>
        {
            var code = ShippingCarrierCodes.Normalize(st.CarrierCode);
            var name = ShippingCarrierCodes.DisplayName(code);
            var client = Resolve(code);
            if (client == null)
                return new List<ShippingCompareQuoteItem> { new(code, name, false, 0, Message: "Adapter chưa đăng ký") };
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(12));
            try
            {
                var opts = await client.QuoteOptionsAsync(st, quoteReq with { CarrierCode = code }, cts.Token);
                return opts.Select(q => new ShippingCompareQuoteItem(
                    code, name, q.Success, q.Fee, q.ServiceName, q.ServiceCode, q.Message,
                    EtaHours: q.EtaMinutes is > 0 ? (int)Math.Ceiling(q.EtaMinutes.Value / 60.0) : null,
                    EtaMinutes: q.EtaMinutes)).ToList();
            }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested)
            {
                return [new(code, name, false, 0, Message: "Hãng phản hồi quá 12 giây")];
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Compare quote failed for {Carrier}", code);
                return new List<ShippingCompareQuoteItem> { new(code, name, false, 0, Message: ex.Message) };
            }
        }).ToList();
        var quotes = (await Task.WhenAll(tasks)).SelectMany(x => x).ToList();
        // Token AhaMove / JWT VTP có thể vừa làm mới.
        await db.SaveChangesAsync(ct);

        quotes = ShippingQuoteRanker.Rank(quotes).ToList();

        // Nội bộ luôn có trong bảng so sánh (phí 0).
        quotes.Add(new ShippingCompareQuoteItem(
            "Internal", "Giao hàng nội bộ", true, 0, ServiceName: "Tự giao", ServiceCode: "internal"));

        var ordered = quotes
            .OrderByDescending(x => x.Success)
            .ThenBy(x => x.Success ? x.Fee : decimal.MaxValue)
            .ThenBy(x => x.CarrierName)
            .ToList();

        return new ShippingCompareResult(order.Id, package, ordered);
    }

    /// <summary>Chữ ký link tải nhãn GHTK (HMAC-SHA256 theo mã bí mật cửa hàng).</summary>
    public static string LabelSignature(string secret, Guid orderId, long exp)
    {
        using var h = new System.Security.Cryptography.HMACSHA256(System.Text.Encoding.UTF8.GetBytes(secret));
        var mac = h.ComputeHash(System.Text.Encoding.UTF8.GetBytes($"{orderId:N}|{exp}"));
        return Convert.ToHexString(mac).ToLowerInvariant();
    }

    /// <summary>Tải PDF nhãn GHTK qua link có chữ ký (không cần đăng nhập, hết hạn theo exp).</summary>
    public async Task<(byte[]? Pdf, string? Error)> DownloadSignedLabelAsync(
        Guid orderId, long exp, string? sig, CancellationToken ct)
    {
        if (DateTimeOffset.UtcNow.ToUnixTimeSeconds() > exp) return (null, "Link đã hết hạn — mở lại từ đơn hàng");
        var order = await db.PosSaleOrders.AsNoTracking()
            .FirstOrDefaultAsync(o => o.Id == orderId && o.Deleted == null && o.IsDelivery, ct);
        if (order == null || string.IsNullOrWhiteSpace(order.DeliveryTrackingCode)) return (null, "Không tìm thấy vận đơn");
        var settings = await db.PosShippingCarrierSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == order.StoreId && x.CarrierCode == ShippingCarrierCodes.Ghtk
                                      && x.Deleted == null, ct);
        var secret = ViettelPostExtraJson.GetWebhookSecret(settings?.ExtraJson);
        if (settings == null || string.IsNullOrWhiteSpace(secret) || string.IsNullOrWhiteSpace(sig))
            return (null, "Không hợp lệ");
        var expect = LabelSignature(secret, orderId, exp);
        if (!System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
                System.Text.Encoding.UTF8.GetBytes(expect), System.Text.Encoding.UTF8.GetBytes(sig.Trim())))
            return (null, "Chữ ký không hợp lệ");
        if (Resolve(ShippingCarrierCodes.Ghtk) is not GhtkShippingClient ghtk) return (null, "Adapter chưa đăng ký");
        return await ghtk.DownloadLabelAsync(settings, order.DeliveryTrackingCode!, ct);
    }

    public async Task<ShippingCreateResult> CreateForOrderAsync(
        Guid storeId, ShippingCreateRequest request, string? userEmail, CancellationToken ct)
    {
        var code = ShippingCarrierCodes.Normalize(request.CarrierCode);
        var settings = await LoadEnabledCarrierAsync(storeId, code, ct);
        if (settings == null)
            return new(false, code, Message: $"Chưa bật / cấu hình {ShippingCarrierCodes.DisplayName(code)}");

        var order = await db.PosSaleOrders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == request.OrderId && o.StoreId == storeId && o.Deleted == null, ct);
        if (order == null)
            return new(false, code, Message: "Không tìm thấy đơn hàng");
        if (!order.IsDelivery)
            return new(false, code, Message: "Đơn không phải đơn giao hàng");
        var reship = order.DeliveryStatusCode == ShipmentStatus.Cancelled;
        if (!string.IsNullOrWhiteSpace(order.DeliveryTrackingCode) && !reship)
            return new(false, code, TrackingCode: order.DeliveryTrackingCode,
                CarrierOrderId: order.DeliveryCarrierOrderId,
                Message: $"Đơn đã có mã vận đơn: {order.DeliveryTrackingCode}");

        // Giữ chỗ «đang tạo»: bấm 2 lần / 2 máy cùng bấm chỉ một yêu cầu gọi hãng
        // (tránh 2 vận đơn, 2 lần tài xế tới lấy).
        var claimAt = DateTime.UtcNow;
        var staleClaim = claimAt.AddMinutes(-2);
        var prevStatusCode = order.DeliveryStatusCode;
        var prevStatusAt = order.DeliveryStatusAt;
        var claimed = await db.PosSaleOrders
            .Where(o => o.Id == order.Id
                && (o.DeliveryTrackingCode == null || o.DeliveryTrackingCode == ""
                    || o.DeliveryStatusCode == ShipmentStatus.Cancelled)
                && !(o.DeliveryStatusCode == ShipmentStatus.Creating && o.DeliveryStatusAt > staleClaim))
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryStatusCode, ShipmentStatus.Creating)
                .SetProperty(o => o.DeliveryStatusAt, claimAt), ct);
        if (claimed == 0)
            return new(false, code, Message: "Đơn đang được tạo vận đơn (máy khác / bấm 2 lần) — đợi vài giây rồi tải lại");

        async Task ReleaseClaimAsync()
        {
            await db.PosSaleOrders.Where(o => o.Id == order.Id && o.DeliveryStatusCode == ShipmentStatus.Creating)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(o => o.DeliveryStatusCode, prevStatusCode)
                    .SetProperty(o => o.DeliveryStatusAt, prevStatusAt), ct);
        }

        var payer = ShippingFeePayer.Normalize(request.ShipFeePayer);
        decimal? appliedFixedFee = null;
        if (payer == ShippingFeePayer.Fixed)
        {
            var fixedFee = Math.Max(0m, request.FixedShipFee ?? 0m);
            if (fixedFee <= 0)
            {
                await ReleaseClaimAsync();
                return new(false, code, Message: "Ship cố định cần số tiền > 0");
            }
            appliedFixedFee = fixedFee;
            var nowFee = DateTime.UtcNow;
            await db.PosSaleOrders.Where(o => o.Id == order.Id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(o => o.DeliveryFee, fixedFee)
                    .SetProperty(o => o.UpdatedAt, nowFee)
                    .SetProperty(o => o.UpdatedBy, userEmail), ct);
            order.DeliveryFee = fixedFee;
        }

        // COD: còn thiếu sau khi đã cộng phí ship cố định (nếu có).
        var effectiveCod = request.CodAmount
            ?? Math.Max(0m, order.PayableTotal - Math.Max(0m, order.PaidAmount));

        var client = Resolve(code);
        if (client == null)
        {
            await ReleaseClaimAsync();
            return new(false, code, Message: "Adapter chưa đăng ký");
        }

        var recv = ShippingAddressNormalizer.FromOrder(order);
        // Backfill quận thiếu (đơn QR 2 cấp) để tạo vận đơn GHTK/GHN.
        if (string.IsNullOrWhiteSpace(order.DeliveryDistrict) && !string.IsNullOrWhiteSpace(recv.District))
        {
            order.DeliveryDistrict = recv.District;
            await db.PosSaleOrders.Where(o => o.Id == order.Id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(o => o.DeliveryDistrict, recv.District), ct);
        }

        var createReq = request with
        {
            CarrierCode = code,
            ShipFeePayer = payer == ShippingFeePayer.Fixed ? ShippingFeePayer.Shop : payer,
            CodAmount = effectiveCod,
            ToProvince = request.ToProvince ?? recv.Province,
            ToDistrict = request.ToDistrict ?? recv.District,
            ToWard = request.ToWard ?? recv.Ward,
        };
        ShippingCreateResult result;
        try
        {
            result = await client.CreateAsync(settings, order, createReq, ct);
        }
        catch
        {
            await ReleaseClaimAsync();
            throw;
        }
        if (string.Equals(code, ShippingCarrierCodes.Ahamove, StringComparison.OrdinalIgnoreCase))
            await db.SaveChangesAsync(ct);
        if (!result.Success)
        {
            await ReleaseClaimAsync();
            return result;
        }

        var tracking = result.TrackingCode;
        var carrierOrderId = result.CarrierOrderId ?? result.TrackingCode;
        var labelUrl = result.LabelUrl;
        // Phí lưu trên đơn: fixed → giữ số cố định; không thì lấy phí hãng / sẵn có.
        var fee = appliedFixedFee
            ?? (result.Fee is > 0 ? result.Fee.Value : order.DeliveryFee);
        var partner = ShippingCarrierCodes.DisplayName(code);
        var now = DateTime.UtcNow;
        var rows = await db.PosSaleOrders.Where(o => o.Id == order.Id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryCarrierCode, code)
                .SetProperty(o => o.DeliveryPartner, partner)
                .SetProperty(o => o.DeliveryTrackingCode, tracking)
                .SetProperty(o => o.DeliveryCarrierOrderId, carrierOrderId)
                .SetProperty(o => o.DeliveryLabelUrl, code == ShippingCarrierCodes.Ghtk ? null : labelUrl)
                .SetProperty(o => o.DeliveryFee, fee)
                .SetProperty(o => o.DeliveryCarrierFee, result.Fee)
                .SetProperty(o => o.DeliveryCodAmount, effectiveCod)
                .SetProperty(o => o.DeliveryFeePayer, payer)
                .SetProperty(o => o.DeliveryServiceName, request.ServiceName ?? request.ServiceCode)
                .SetProperty(o => o.DeliveryShippedAt, now)
                // Tạo lại sau khi hủy: xóa mốc cũ của vận đơn trước.
                .SetProperty(o => o.DeliveryStatusCode, (string?)null)
                .SetProperty(o => o.DeliveryFailCount, 0)
                .SetProperty(o => o.DeliveryLastReason, (string?)null)
                .SetProperty(o => o.DeliveryCancelledAt, (DateTime?)null)
                .SetProperty(o => o.DeliveryPickedAt, (DateTime?)null)
                .SetProperty(o => o.DeliveryCodSettledAt, (DateTime?)null)
                .SetProperty(o => o.UpdatedAt, now)
                .SetProperty(o => o.UpdatedBy, userEmail), ct);

        if (rows <= 0)
        {
            logger.LogWarning(
                "Shipping create Persist 0 rows {Carrier} order {OrderNo} tracking {Tracking}",
                code, order.OrderNo, tracking);
            return result with
            {
                Success = false,
                Message = $"Tạo vận đơn {tracking} OK trên hãng nhưng không lưu được vào đơn SBOX — thử lại.",
            };
        }

        await ApplyShipmentStatusAsync(order.Id, code, ShipmentStatus.Created,
            request.ServiceName ?? request.ServiceCode, null, "create", userEmail, ct);
        logger.LogInformation("Shipping created {Carrier} order {OrderNo} tracking {Tracking}",
            code, order.OrderNo, result.TrackingCode);
        return result;
    }

    /// <summary>Cập nhật trạng thái giao từ webhook hãng (GHN/GHTK/…).</summary>
    public async Task<bool> ApplyWebhookStatusAsync(
        string carrierCode, string? trackingCode, string? carrierOrderId,
        string? statusText, CancellationToken ct, string? reason = null)
    {
        var code = ShippingCarrierCodes.Normalize(carrierCode);
        var order = await FindOrderByTrackingAsync(trackingCode ?? carrierOrderId, null, ct)
                    ?? await FindOrderByTrackingAsync(carrierOrderId, null, ct);
        if (order == null) return false;
        int? num = int.TryParse(statusText, out var n) ? n : null;
        var mapped = ShipmentStatus.FromCarrier(code, statusText, num);
        var raw = code == ShippingCarrierCodes.Ahamove ? AhamoveWebhookHelper.DisplayName(statusText) : statusText;
        return await ApplyShipmentStatusAsync(order.Id, code, mapped, raw, reason, "webhook", null, ct);
    }

    /// <summary>Webhook Viettel Post — cập nhật trạng thái vận đơn / đơn QR online.</summary>
    public async Task<bool> ApplyViettelPostWebhookAsync(
        string? trackingCode, int? statusCode, string? statusName, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(trackingCode))
            return false;

        var t = trackingCode.Trim();
        var order = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.Deleted == null && o.IsDelivery
                        && (o.DeliveryTrackingCode == t || o.DeliveryCarrierOrderId == t))
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);
        if (order == null) return false;

        await ApplyViettelPostStatusToOrderAsync(order.Id, order, statusCode, statusName, ct);
        return true;
    }

    async Task ApplyViettelPostStatusToOrderAsync(
        Guid orderId, PosSaleOrder orderSnapshot, int? statusCode, string? statusName,
        CancellationToken ct, string source = "webhook")
    {
        var mapped = ShipmentStatus.FromViettelPost(statusCode);
        var raw = statusCode == null ? statusName : $"{statusCode} {statusName}".Trim();
        await ApplyShipmentStatusAsync(orderId, ShippingCarrierCodes.ViettelPost, mapped, raw,
            mapped is ShipmentStatus.DeliveryFailed or ShipmentStatus.Returning or ShipmentStatus.Cancelled
                ? statusName : null,
            source, null, ct);
    }

    ViettelPostShippingClient? ViettelClient() =>
        Resolve(ShippingCarrierCodes.ViettelPost) as ViettelPostShippingClient;

    AhamoveShippingClient? AhamoveClient() =>
        Resolve(ShippingCarrierCodes.Ahamove) as AhamoveShippingClient;

    SpxShippingClient? SpxClient() =>
        Resolve(ShippingCarrierCodes.Spx) as SpxShippingClient;

    static string? FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v));

    async Task<(PosShippingCarrierSetting? Settings, string? Error)> GetEnabledSettingsAsync(
        Guid storeId, string carrierCode, CancellationToken ct)
    {
        var code = ShippingCarrierCodes.Normalize(carrierCode);
        var settings = await db.PosShippingCarrierSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.CarrierCode == code
                                      && x.Deleted == null && x.Enabled, ct);
        if (settings == null)
            return (null, $"Chưa bật / cấu hình {ShippingCarrierCodes.DisplayName(code)}");
        return (settings, null);
    }

    async Task<PosSaleOrder?> FindDeliveryOrderAsync(
        Guid storeId, Guid orderId, CancellationToken ct) =>
        await db.PosSaleOrders
            .FirstOrDefaultAsync(o => o.Id == orderId && o.StoreId == storeId
                                      && o.Deleted == null && o.IsDelivery, ct);

    public Task<bool> ValidateViettelPostWebhookAuthAsync(
        string? authorization, string? bodyToken, string? trackingCode, CancellationToken ct) =>
        AuthorizeWebhookAsync(ShippingCarrierCodes.ViettelPost, trackingCode, null, bodyToken, authorization, ct);

    public Task<bool> ValidateGhtkWebhookHashAsync(
        string? queryHash, string? labelId, string? partnerId, CancellationToken ct) =>
        AuthorizeWebhookAsync(ShippingCarrierCodes.Ghtk, labelId, partnerId, queryHash, null, ct);

    public async Task<bool> ApplyGhtkWebhookAsync(
        string? labelId, string? partnerId, int? statusId, string? reasonOrText, CancellationToken ct)
    {
        var order = await FindOrderByTrackingAsync(labelId, partnerId, ct);
        if (order == null) return false;
        var label = (labelId ?? "").Trim();
        if (string.IsNullOrWhiteSpace(order.DeliveryTrackingCode) && label.Length > 0)
        {
            await db.PosSaleOrders.Where(o => o.Id == order.Id)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.DeliveryTrackingCode, label), ct);
        }
        var mapped = ShipmentStatus.FromGhtk(statusId);
        var raw = GhtkWebhookHelper.StatusLabel(statusId);
        return await ApplyShipmentStatusAsync(order.Id, ShippingCarrierCodes.Ghtk, mapped, raw,
            string.IsNullOrWhiteSpace(reasonOrText) ? null : reasonOrText, "webhook", null, ct);
    }

    public Task<bool> ValidateSpxWebhookHashAsync(
        string? queryHash, string? trackingCode, CancellationToken ct) =>
        AuthorizeWebhookAsync(ShippingCarrierCodes.Spx, trackingCode, null, queryHash, null, ct);

    public async Task<bool> ApplySpxWebhookAsync(
        string? trackingCode, string? statusText, CancellationToken ct)
    {
        var order = await FindOrderByTrackingAsync(trackingCode, null, ct);
        if (order == null) return false;
        return await ApplyShipmentStatusAsync(order.Id, ShippingCarrierCodes.Spx,
            ShipmentStatus.FromSpx(statusText), SpxWebhookHelper.StatusLabel(statusText), null, "webhook", null, ct);
    }

    public async Task<IReadOnlyList<ShippingAddressItem>> ListViettelPostAddressesAsync(
        Guid storeId, string level, int? parentId, CancellationToken ct)
    {
        var (settings, err) = await GetEnabledSettingsAsync(storeId, ShippingCarrierCodes.ViettelPost, ct);
        if (settings == null || err != null) return [];
        var client = ViettelClient();
        if (client == null) return [];

        return level.ToLowerInvariant() switch
        {
            "district" or "districts" when parentId is > 0 =>
                await client.ListDistrictsAsync(settings, parentId.Value, ct),
            "ward" or "wards" when parentId is > 0 =>
                await client.ListWardsAsync(settings, parentId.Value, ct),
            _ => await client.ListProvincesAsync(settings, ct),
        };
    }

    public async Task<ShippingLabelResult> GetShipmentLabelAsync(
        Guid storeId, Guid orderId, CancellationToken ct)
    {
        var order = await FindDeliveryOrderAsync(storeId, orderId, ct);
        if (order == null)
            return new(false, "", Message: "Không tìm thấy đơn giao hàng");
        if (string.IsNullOrWhiteSpace(order.DeliveryTrackingCode))
            return new(false, order.DeliveryCarrierCode ?? "", Message: "Đơn chưa có mã vận đơn");

        var code = ShippingCarrierCodes.Normalize(order.DeliveryCarrierCode ?? "");
        if (string.Equals(code, ShippingCarrierCodes.Spx, StringComparison.OrdinalIgnoreCase))
            return await GetSpxLabelAsync(storeId, order, ct);
        if (code == ShippingCarrierCodes.Ghn)
        {
            var (ghnSettings, ghnErr) = await GetEnabledSettingsAsync(storeId, code, ct);
            if (ghnSettings == null) return new(false, code, Message: ghnErr);
            if (Resolve(code) is not GhnShippingClient ghn) return new(false, code, Message: "Adapter chưa đăng ký");
            return await ghn.GetPrintLabelAsync(ghnSettings, order.DeliveryTrackingCode!, ct);
        }
        if (code == ShippingCarrierCodes.Ghtk)
        {
            // Nhãn GHTK cần Token hãng → trả link SBOX có chữ ký (hết hạn 30 phút) để máy bán mở PDF.
            var secret = await EnsureWebhookSecretAsync(storeId, code, ct);
            if (string.IsNullOrWhiteSpace(secret)) return new(false, code, Message: "Chưa cấu hình GHTK");
            var exp = DateTimeOffset.UtcNow.AddMinutes(30).ToUnixTimeSeconds();
            return new(true, code,
                LabelUrl: $"/api/pos/shipping/label-file/{order.Id}?exp={exp}&sig={LabelSignature(secret, order.Id, exp)}",
                Message: "Nhãn GHTK (PDF)");
        }
        if (!string.Equals(code, ShippingCarrierCodes.ViettelPost, StringComparison.OrdinalIgnoreCase))
        {
            if (!string.IsNullOrWhiteSpace(order.DeliveryLabelUrl))
                return new(true, code, LabelUrl: order.DeliveryLabelUrl, Message: "Link in đã lưu");
            return new(false, code, Message: "Hãng vận chuyển chưa hỗ trợ in nhãn qua API");
        }

        var (settings, err) = await GetEnabledSettingsAsync(storeId, code, ct);
        if (settings == null)
            return new(false, code, Message: err);

        var client = ViettelClient();
        if (client == null)
            return new(false, code, Message: "Adapter chưa đăng ký");

        var result = await client.GetPrintLabelAsync(settings, order.DeliveryTrackingCode!, ct);
        if (result.Success && !string.IsNullOrWhiteSpace(result.LabelUrl))
        {
            await db.PosSaleOrders.Where(o => o.Id == order.Id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(o => o.DeliveryLabelUrl, result.LabelUrl)
                    .SetProperty(o => o.UpdatedAt, DateTime.UtcNow), ct);
        }
        return result;
    }

    public async Task<ShippingCancelResult> CancelShipmentAsync(
        Guid storeId, Guid orderId, string? note, string? userEmail, CancellationToken ct)
    {
        var order = await FindDeliveryOrderAsync(storeId, orderId, ct);
        if (order == null)
            return new(false, "", Message: "Không tìm thấy đơn giao hàng");
        if (string.IsNullOrWhiteSpace(order.DeliveryTrackingCode)
            && string.IsNullOrWhiteSpace(order.DeliveryCarrierOrderId))
            return new(false, order.DeliveryCarrierCode ?? "", Message: "Đơn chưa có mã vận đơn");

        var code = ShippingCarrierCodes.Normalize(order.DeliveryCarrierCode ?? "");
        if (order.DeliveryStatusCode == ShipmentStatus.Cancelled)
            return new(true, code, Message: "Vận đơn đã hủy trước đó");
        if (string.Equals(code, ShippingCarrierCodes.Ahamove, StringComparison.OrdinalIgnoreCase))
            return await CancelAhamoveAsync(storeId, order, note, userEmail, ct);
        if (string.Equals(code, ShippingCarrierCodes.Spx, StringComparison.OrdinalIgnoreCase))
            return await CancelSpxAsync(storeId, order, note, userEmail, ct);
        if (code is ShippingCarrierCodes.Ghn or ShippingCarrierCodes.Ghtk)
        {
            var (cs, cerr) = await GetEnabledSettingsAsync(storeId, code, ct);
            if (cs == null) return new(false, code, Message: cerr);
            var trackingNo = FirstNonEmpty(order.DeliveryTrackingCode, order.DeliveryCarrierOrderId)!;
            var cancelResult = Resolve(code) switch
            {
                GhnShippingClient ghn => await ghn.CancelOrderAsync(cs, trackingNo, ct),
                GhtkShippingClient ghtk => await ghtk.CancelOrderAsync(cs, trackingNo, ct),
                _ => new ShippingCancelResult(false, code, "Adapter chưa đăng ký"),
            };
            if (cancelResult.Success)
                await ApplyShipmentStatusAsync(order.Id, code, ShipmentStatus.Cancelled, "cancel",
                    note ?? "Shop hủy vận đơn", "cancel", userEmail, ct);
            return cancelResult;
        }
        if (!string.Equals(code, ShippingCarrierCodes.ViettelPost, StringComparison.OrdinalIgnoreCase))
            return new(false, code, Message: "Hãng này chưa hỗ trợ hủy vận đơn qua API");

        var (settings, err) = await GetEnabledSettingsAsync(storeId, code, ct);
        if (settings == null)
            return new(false, code, Message: err);

        var client = ViettelClient();
        if (client == null)
            return new(false, code, Message: "Adapter chưa đăng ký");

        var result = await client.UpdateOrderStatusAsync(
            settings, order.DeliveryTrackingCode!, type: 4, note, ct);
        if (!result.Success) return result;

        await ApplyShipmentStatusAsync(order.Id, order.DeliveryCarrierCode ?? "", ShipmentStatus.Cancelled,
            "cancel", note ?? "Shop hủy vận đơn", "cancel", userEmail, ct);
        return result;
    }

    async Task<ShippingCancelResult> CancelAhamoveAsync(
        Guid storeId, PosSaleOrder order, string? note, string? userEmail, CancellationToken ct)
    {
        var settings = await LoadEnabledCarrierAsync(storeId, ShippingCarrierCodes.Ahamove, ct);
        if (settings == null)
            return new(false, ShippingCarrierCodes.Ahamove, Message: "Chưa bật / cấu hình AhaMove");
        var client = AhamoveClient();
        if (client == null)
            return new(false, ShippingCarrierCodes.Ahamove, Message: "Adapter chưa đăng ký");

        var ahaId = FirstNonEmpty(order.DeliveryCarrierOrderId, order.DeliveryTrackingCode)!;
        var result = await client.CancelOrderAsync(settings, ahaId, note, ct);
        await db.SaveChangesAsync(ct);
        if (!result.Success) return result;

        await ApplyShipmentStatusAsync(order.Id, order.DeliveryCarrierCode ?? "", ShipmentStatus.Cancelled,
            "cancel", note ?? "Shop hủy vận đơn", "cancel", userEmail, ct);
        return result;
    }

    public async Task<ShippingTrackingResult> SyncTrackingAsync(
        Guid storeId, Guid orderId, string? userEmail, CancellationToken ct)
    {
        var order = await FindDeliveryOrderAsync(storeId, orderId, ct);
        if (order == null)
            return new(false, "", Message: "Không tìm thấy đơn giao hàng");
        if (string.IsNullOrWhiteSpace(order.DeliveryTrackingCode)
            && string.IsNullOrWhiteSpace(order.DeliveryCarrierOrderId))
            return new(false, order.DeliveryCarrierCode ?? "", Message: "Đơn chưa có mã vận đơn");

        var code = ShippingCarrierCodes.Normalize(order.DeliveryCarrierCode ?? "");
        if (string.Equals(code, ShippingCarrierCodes.Ahamove, StringComparison.OrdinalIgnoreCase))
            return await SyncAhamoveTrackingAsync(storeId, order, userEmail, ct);
        if (code is ShippingCarrierCodes.Ghn or ShippingCarrierCodes.Ghtk)
        {
            var (ts, terr) = await GetEnabledSettingsAsync(storeId, code, ct);
            if (ts == null) return new(false, code, Message: terr);
            var trackingNo = FirstNonEmpty(order.DeliveryTrackingCode, order.DeliveryCarrierOrderId)!;
            var tr = Resolve(code) switch
            {
                GhnShippingClient ghn => await ghn.GetTrackingAsync(ts, trackingNo, ct),
                GhtkShippingClient ghtk => await ghtk.GetTrackingAsync(ts, trackingNo, ct),
                _ => new ShippingTrackingResult(false, code, Message: "Adapter chưa đăng ký"),
            };
            if (!tr.Success) return tr;
            var mappedCode = ShipmentStatus.FromCarrier(code, tr.StatusName, tr.StatusCode);
            await ApplyShipmentStatusAsync(order.Id, code, mappedCode, tr.StatusName, null, "sync", userEmail, ct);
            return tr with { MappedOnlineStatus = mappedCode };
        }
        if (string.Equals(code, ShippingCarrierCodes.Spx, StringComparison.OrdinalIgnoreCase))
            return await SyncSpxTrackingAsync(storeId, order, userEmail, ct);
        if (!string.Equals(code, ShippingCarrierCodes.ViettelPost, StringComparison.OrdinalIgnoreCase))
            return new(false, code, Message: "Hãng này chưa hỗ trợ đồng bộ hành trình qua API");

        var (settings, err) = await GetEnabledSettingsAsync(storeId, code, ct);
        if (settings == null)
            return new(false, code, Message: err);

        var client = ViettelClient();
        if (client == null)
            return new(false, code, Message: "Adapter chưa đăng ký");

        var tracking = await client.GetTrackingAsync(settings, order.DeliveryTrackingCode!, ct);
        if (!tracking.Success) return tracking;

        await ApplyViettelPostStatusToOrderAsync(
            order.Id, order, tracking.StatusCode, tracking.StatusName, ct, "sync");
        return tracking;
    }

    async Task<ShippingTrackingResult> SyncAhamoveTrackingAsync(
        Guid storeId, PosSaleOrder order, string? userEmail, CancellationToken ct)
    {
        var settings = await LoadEnabledCarrierAsync(storeId, ShippingCarrierCodes.Ahamove, ct);
        if (settings == null)
            return new(false, ShippingCarrierCodes.Ahamove, Message: "Chưa bật / cấu hình AhaMove");
        var client = AhamoveClient();
        if (client == null)
            return new(false, ShippingCarrierCodes.Ahamove, Message: "Adapter chưa đăng ký");

        var ahaId = FirstNonEmpty(order.DeliveryCarrierOrderId, order.DeliveryTrackingCode)!;
        var tracking = await client.GetTrackingAsync(settings, ahaId, ct);
        await db.SaveChangesAsync(ct);
        if (!tracking.Success) return tracking;

        await ApplyAhamoveStatusToOrderAsync(order.Id, order, tracking, userEmail, ct);
        return tracking;
    }

    async Task ApplyAhamoveStatusToOrderAsync(
        Guid orderId, PosSaleOrder orderSnapshot, ShippingTrackingResult tracking,
        string? userEmail, CancellationToken ct)
    {
        string? labelUrl = null;
        // StatusName là nhãn tiếng Việt — quy đổi trạng thái cần mã gốc của AhaMove (COMPLETED, FAILED…).
        string? rawStatus = null;
        if (!string.IsNullOrWhiteSpace(tracking.RawJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(tracking.RawJson);
                var root = doc.RootElement;
                var orderEl = root.TryGetProperty("order", out var o0) && o0.ValueKind == JsonValueKind.Object ? o0 : root;
                rawStatus = AhamoveWebhookHelper.EffectiveStatus(orderEl);
                if (root.TryGetProperty("shared_link", out var sl) && sl.ValueKind == JsonValueKind.String)
                    labelUrl = sl.GetString();
                else if (root.TryGetProperty("order", out var ord) &&
                         ord.TryGetProperty("shared_link", out var sl2) && sl2.ValueKind == JsonValueKind.String)
                    labelUrl = sl2.GetString();
            }
            catch { /* ignore */ }
        }
        if (!string.IsNullOrWhiteSpace(labelUrl))
        {
            await db.PosSaleOrders.Where(o => o.Id == orderId)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.DeliveryLabelUrl, labelUrl), ct);
        }
        var status = rawStatus ?? tracking.StatusName;
        await ApplyShipmentStatusAsync(orderId, ShippingCarrierCodes.Ahamove,
            ShipmentStatus.FromAhamove(status), AhamoveWebhookHelper.DisplayName(status),
            null, "sync", userEmail, ct);
    }

    async Task<ShippingLabelResult> GetSpxLabelAsync(
        Guid storeId, PosSaleOrder order, CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(order.DeliveryLabelUrl))
            return new(true, ShippingCarrierCodes.Spx, LabelUrl: order.DeliveryLabelUrl, Message: "Link in đã lưu");

        var (settings, err) = await GetEnabledSettingsAsync(storeId, ShippingCarrierCodes.Spx, ct);
        if (settings == null)
            return new(false, ShippingCarrierCodes.Spx, Message: err);
        var client = SpxClient();
        if (client == null)
            return new(false, ShippingCarrierCodes.Spx, Message: "Adapter chưa đăng ký");

        var tn = FirstNonEmpty(order.DeliveryTrackingCode, order.DeliveryCarrierOrderId)!;
        var result = await client.GetPrintLabelAsync(settings, tn, ct);
        if (result.Success && !string.IsNullOrWhiteSpace(result.LabelUrl))
        {
            await db.PosSaleOrders.Where(o => o.Id == order.Id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(o => o.DeliveryLabelUrl, result.LabelUrl)
                    .SetProperty(o => o.UpdatedAt, DateTime.UtcNow), ct);
        }
        return result;
    }

    async Task<ShippingCancelResult> CancelSpxAsync(
        Guid storeId, PosSaleOrder order, string? note, string? userEmail, CancellationToken ct)
    {
        var settings = await LoadEnabledCarrierAsync(storeId, ShippingCarrierCodes.Spx, ct);
        if (settings == null)
            return new(false, ShippingCarrierCodes.Spx, Message: "Chưa bật / cấu hình SPX Express");
        var client = SpxClient();
        if (client == null)
            return new(false, ShippingCarrierCodes.Spx, Message: "Adapter chưa đăng ký");

        var tn = FirstNonEmpty(order.DeliveryTrackingCode, order.DeliveryCarrierOrderId)!;
        var result = await client.CancelOrderAsync(settings, tn, note, ct);
        if (!result.Success) return result;

        await ApplyShipmentStatusAsync(order.Id, order.DeliveryCarrierCode ?? "", ShipmentStatus.Cancelled,
            "cancel", note ?? "Shop hủy vận đơn", "cancel", userEmail, ct);
        return result;
    }

    async Task<ShippingTrackingResult> SyncSpxTrackingAsync(
        Guid storeId, PosSaleOrder order, string? userEmail, CancellationToken ct)
    {
        var settings = await LoadEnabledCarrierAsync(storeId, ShippingCarrierCodes.Spx, ct);
        if (settings == null)
            return new(false, ShippingCarrierCodes.Spx, Message: "Chưa bật / cấu hình SPX Express");
        var client = SpxClient();
        if (client == null)
            return new(false, ShippingCarrierCodes.Spx, Message: "Adapter chưa đăng ký");

        var tn = FirstNonEmpty(order.DeliveryTrackingCode, order.DeliveryCarrierOrderId)!;
        var tracking = await client.GetTrackingAsync(settings, tn, ct);
        if (!tracking.Success) return tracking;

        await ApplyShipmentStatusAsync(order.Id, ShippingCarrierCodes.Spx,
            ShipmentStatus.FromSpx(tracking.StatusName), SpxWebhookHelper.StatusLabel(tracking.StatusName),
            null, "sync", userEmail, ct);
        return tracking;
    }
}
