using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.Shipping;

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
    string? ExtraJson);

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

public class PosShippingService(
    ZKTecoDbContext db,
    IEnumerable<IShippingCarrierClient> carriers,
    ILogger<PosShippingService> logger)
{
    IShippingCarrierClient? Resolve(string code) =>
        carriers.FirstOrDefault(c =>
            c.CarrierCode.Equals(ShippingCarrierCodes.Normalize(code), StringComparison.OrdinalIgnoreCase));

    public async Task<List<ShippingCarrierSettingDto>> ListSettingsAsync(Guid storeId, CancellationToken ct)
    {
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
        s.ExtraJson);
    }

    /// <summary>Sau lưu Viettel Post — thử login lấy JWT lưu vào ApiToken (tạo vận đơn).</summary>
    async Task<string?> TryRefreshViettelJwtAsync(PosShippingCarrierSetting row, CancellationToken ct)
    {
        if (!string.Equals(row.CarrierCode, ShippingCarrierCodes.ViettelPost, StringComparison.OrdinalIgnoreCase))
            return null;
        if (string.IsNullOrWhiteSpace(row.Username) || string.IsNullOrWhiteSpace(row.Password))
            return null;
        var client = Resolve(ShippingCarrierCodes.ViettelPost) as ViettelPostShippingClient;
        if (client == null) return null;
        var (jwt, err) = await client.TryLoginSessionTokenAsync(row, ct);
        if (!string.IsNullOrWhiteSpace(jwt))
        {
            row.ApiToken = jwt;
            row.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
            logger.LogInformation("ViettelPost JWT refreshed for store {StoreId}", row.StoreId);
            return "Đã lấy JWT Viettel Post — có thể tạo vận đơn.";
        }
        return err ?? "Không lấy được JWT Viettel Post — kiểm tra Username/Mật khẩu.";
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
        if (!string.IsNullOrWhiteSpace(req.Password))
            notice = await TryRefreshViettelJwtAsync(row, ct);
        return ToDto(row, notice);
    }

    static string? NullIfEmpty(string? v) =>
        string.IsNullOrWhiteSpace(v) ? null : v.Trim();

    public async Task<ShippingQuoteResult> QuoteAsync(
        Guid storeId, ShippingQuoteRequest request, CancellationToken ct)
    {
        var code = ShippingCarrierCodes.Normalize(request.CarrierCode);
        var settings = await db.PosShippingCarrierSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.CarrierCode == code
                                      && x.Deleted == null && x.Enabled, ct);
        if (settings == null)
            return new(false, code, 0, Message: $"Chưa bật / cấu hình {ShippingCarrierCodes.DisplayName(code)}");
        var client = Resolve(code);
        if (client == null)
            return new(false, code, 0, Message: "Adapter chưa đăng ký");
        return await client.QuoteAsync(settings, request with { CarrierCode = code }, ct);
    }

    public async Task<ShippingCreateResult> CreateForOrderAsync(
        Guid storeId, ShippingCreateRequest request, string? userEmail, CancellationToken ct)
    {
        var code = ShippingCarrierCodes.Normalize(request.CarrierCode);
        var settings = await db.PosShippingCarrierSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.CarrierCode == code
                                      && x.Deleted == null && x.Enabled, ct);
        if (settings == null)
            return new(false, code, Message: $"Chưa bật / cấu hình {ShippingCarrierCodes.DisplayName(code)}");

        var order = await db.PosSaleOrders
            .FirstOrDefaultAsync(o => o.Id == request.OrderId && o.StoreId == storeId && o.Deleted == null, ct);
        if (order == null)
            return new(false, code, Message: "Không tìm thấy đơn hàng");
        if (!order.IsDelivery)
            return new(false, code, Message: "Đơn không phải đơn giao hàng");
        if (!string.IsNullOrWhiteSpace(order.DeliveryTrackingCode))
            return new(false, code, TrackingCode: order.DeliveryTrackingCode,
                CarrierOrderId: order.DeliveryCarrierOrderId,
                Message: $"Đơn đã có mã vận đơn: {order.DeliveryTrackingCode}");

        var client = Resolve(code);
        if (client == null)
            return new(false, code, Message: "Adapter chưa đăng ký");

        var result = await client.CreateAsync(settings, order, request with { CarrierCode = code }, ct);
        if (!result.Success) return result;

        order.DeliveryCarrierCode = code;
        order.DeliveryPartner = ShippingCarrierCodes.DisplayName(code);
        order.DeliveryTrackingCode = result.TrackingCode;
        order.DeliveryCarrierOrderId = result.CarrierOrderId ?? result.TrackingCode;
        order.DeliveryLabelUrl = result.LabelUrl;
        order.DeliveryStatus = "Đã tạo vận đơn";
        if (result.Fee is > 0)
            order.DeliveryFee = result.Fee.Value;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = userEmail;
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Shipping created {Carrier} order {OrderNo} tracking {Tracking}",
            code, order.OrderNo, result.TrackingCode);
        return result;
    }

    /// <summary>Cập nhật trạng thái giao từ webhook hãng (GHN/GHTK/…).</summary>
    public async Task<bool> ApplyWebhookStatusAsync(
        string carrierCode, string? trackingCode, string? carrierOrderId,
        string? statusText, CancellationToken ct)
    {
        var code = ShippingCarrierCodes.Normalize(carrierCode);
        if (string.IsNullOrWhiteSpace(trackingCode) && string.IsNullOrWhiteSpace(carrierOrderId))
            return false;

        var q = db.PosSaleOrders.Where(o => o.Deleted == null && o.IsDelivery);
        if (!string.IsNullOrWhiteSpace(trackingCode))
        {
            var t = trackingCode.Trim();
            q = q.Where(o => o.DeliveryTrackingCode == t || o.DeliveryCarrierOrderId == t);
        }
        else if (!string.IsNullOrWhiteSpace(carrierOrderId))
        {
            var id = carrierOrderId.Trim();
            q = q.Where(o => o.DeliveryCarrierOrderId == id || o.DeliveryTrackingCode == id);
        }

        var order = await q.OrderByDescending(o => o.CreatedAt).FirstOrDefaultAsync(ct);
        if (order == null) return false;

        if (string.IsNullOrWhiteSpace(order.DeliveryCarrierCode))
            order.DeliveryCarrierCode = code;
        if (!string.IsNullOrWhiteSpace(statusText))
            order.DeliveryStatus = statusText.Trim();
        order.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Shipping webhook {Carrier} {Tracking} → {Status}",
            code, trackingCode ?? carrierOrderId, statusText);
        return true;
    }
}
