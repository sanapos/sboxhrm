using Microsoft.EntityFrameworkCore;
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

        var enabled = await db.PosShippingCarrierSettings.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Enabled)
            .Select(x => x.CarrierCode)
            .ToListAsync(ct);

        var quotes = new List<ShippingCompareQuoteItem>();
        foreach (var codeRaw in enabled)
        {
            var code = ShippingCarrierCodes.Normalize(codeRaw);
            try
            {
                var q = await QuoteAsync(storeId, new ShippingQuoteRequest(
                    code,
                    order.CustomerName ?? "Khách",
                    order.DeliveryPhone ?? "",
                    string.IsNullOrWhiteSpace(recv.Address)
                        ? (order.DeliveryAddress ?? "")
                        : recv.Address,
                    recv.Province,
                    recv.District,
                    recv.Ward,
                    WeightGrams: package.ChargeableWeightGrams,
                    CodAmount: Math.Max(0, cod),
                    InsuranceValue: insurance,
                    LengthCm: package.LengthCm,
                    WidthCm: package.WidthCm,
                    HeightCm: package.HeightCm), ct);
                quotes.Add(new ShippingCompareQuoteItem(
                    code,
                    ShippingCarrierCodes.DisplayName(code),
                    q.Success,
                    q.Fee,
                    q.ServiceName,
                    q.ServiceCode,
                    q.Message));
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Compare quote failed for {Carrier}", code);
                quotes.Add(new ShippingCompareQuoteItem(
                    code, ShippingCarrierCodes.DisplayName(code), false, 0, Message: ex.Message));
            }
        }

        // Nội bộ luôn có trong bảng so sánh (phí 0).
        quotes.Add(new ShippingCompareQuoteItem(
            "Internal",
            "Giao hàng nội bộ",
            true, 0, ServiceName: "Tự giao", ServiceCode: "internal"));

        var ordered = quotes
            .OrderByDescending(x => x.Success)
            .ThenBy(x => x.Success ? x.Fee : decimal.MaxValue)
            .ThenBy(x => x.CarrierName)
            .ToList();

        return new ShippingCompareResult(order.Id, package, ordered);
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
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == request.OrderId && o.StoreId == storeId && o.Deleted == null, ct);
        if (order == null)
            return new(false, code, Message: "Không tìm thấy đơn hàng");
        if (!order.IsDelivery)
            return new(false, code, Message: "Đơn không phải đơn giao hàng");
        if (!string.IsNullOrWhiteSpace(order.DeliveryTrackingCode))
            return new(false, code, TrackingCode: order.DeliveryTrackingCode,
                CarrierOrderId: order.DeliveryCarrierOrderId,
                Message: $"Đơn đã có mã vận đơn: {order.DeliveryTrackingCode}");

        var payer = ShippingFeePayer.Normalize(request.ShipFeePayer);
        decimal? appliedFixedFee = null;
        if (payer == ShippingFeePayer.Fixed)
        {
            var fixedFee = Math.Max(0m, request.FixedShipFee ?? 0m);
            if (fixedFee <= 0)
                return new(false, code, Message: "Ship cố định cần số tiền > 0");
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
            return new(false, code, Message: "Adapter chưa đăng ký");

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
        var result = await client.CreateAsync(settings, order, createReq, ct);
        if (!result.Success) return result;

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
                .SetProperty(o => o.DeliveryLabelUrl, labelUrl)
                .SetProperty(o => o.DeliveryStatus, "Đã tạo vận đơn")
                .SetProperty(o => o.DeliveryFee, fee)
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

        var q = db.PosSaleOrders.AsNoTracking().Where(o => o.Deleted == null && o.IsDelivery);
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

        var status = string.IsNullOrWhiteSpace(statusText) ? order.DeliveryStatus : statusText.Trim();
        if (string.IsNullOrWhiteSpace(order.DeliveryCarrierCode))
        {
            await db.PosSaleOrders.Where(o => o.Id == order.Id)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.DeliveryCarrierCode, code), ct);
        }

        var rows = await db.PosSaleOrders.Where(o => o.Id == order.Id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryStatus, status)
                .SetProperty(o => o.UpdatedAt, DateTime.UtcNow), ct);

        logger.LogInformation("Shipping webhook {Carrier} {Tracking} → {Status} ({Rows} row)",
            code, trackingCode ?? carrierOrderId, status, rows);
        return rows > 0;
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
        CancellationToken ct)
    {
        var isOnline = string.Equals(orderSnapshot.SalesChannel, QrOnlineOrderStatuses.Channel,
            StringComparison.OrdinalIgnoreCase);
        var mapped = ViettelPostWebhookHelper.MapOnlineStatus(statusCode);
        var prev = isOnline ? QrOnlineOrderStatuses.Normalize(orderSnapshot.DeliveryStatus) : null;

        string newStatus;
        if (isOnline && mapped != null)
        {
            if (QrOnlineOrderStatuses.IsTerminal(prev) && mapped != prev)
            {
                logger.LogInformation(
                    "ViettelPost status skip terminal {OrderNo} {Prev} → {Next}",
                    orderSnapshot.OrderNo, prev, mapped);
                return;
            }
            newStatus = mapped;
        }
        else if (!string.IsNullOrWhiteSpace(statusName))
            newStatus = statusName.Trim();
        else if (mapped != null)
            newStatus = QrOnlineOrderStatuses.Label(mapped);
        else
            newStatus = orderSnapshot.DeliveryStatus ?? QrOnlineOrderStatuses.Shipping;

        var now = DateTime.UtcNow;
        var rows = await db.PosSaleOrders.Where(o => o.Id == orderId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryStatus, newStatus)
                .SetProperty(o => o.UpdatedAt, now)
                .SetProperty(o => o.DeliveryCarrierCode,
                    o => string.IsNullOrWhiteSpace(o.DeliveryCarrierCode)
                        ? ShippingCarrierCodes.ViettelPost
                        : o.DeliveryCarrierCode)
                .SetProperty(o => o.DeliveryDate,
                    o => newStatus == QrOnlineOrderStatuses.Delivered
                        ? o.DeliveryDate ?? now
                        : o.DeliveryDate), ct);

        if (isOnline && mapped == QrOnlineOrderStatuses.Cancelled
            && orderSnapshot.Status == PosSaleOrderStatus.Draft)
        {
            await db.PosSaleOrders.Where(o => o.Id == orderId)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(o => o.Status, PosSaleOrderStatus.Cancelled), ct);
        }
        else if (isOnline && mapped == QrOnlineOrderStatuses.Cancelled
                 && orderSnapshot.Status == PosSaleOrderStatus.Completed)
        {
            // Webhook hủy sau thanh toán: hoàn kho/DT — tránh DT ảo + trừ kho lệch.
            var order = await db.PosSaleOrders.AsTracking()
                .Include(o => o.Lines)
                .FirstOrDefaultAsync(o => o.Id == orderId && o.Deleted == null, ct);
            if (order != null && order.Status == PosSaleOrderStatus.Completed)
            {
                var stockFullyReversed =
                    await PosSaleStockHelper.IsSaleStockFullyReversedAsync(db, order.StoreId, order);
                if (!stockFullyReversed)
                    await PosSaleStockHelper.ReverseSaleOrderAsync(
                        db, order.StoreId, order, "shipping-webhook");
                await PosSaleStockHelper.ReverseCustomerOnSaleCancelAsync(db, order.StoreId, order);
                await PosCustomerFinanceHelper.ReversePointsOnSaleCancelAsync(
                    db, order.StoreId, order, "shipping-webhook");
                await PosFinanceSyncHelper.ReverseSaleOnCancelAsync(db, order);
                await PosSaleWarrantyHelper.VoidOrderAsync(
                    db, order.StoreId, order.Id, "shipping-webhook");
                order.Status = PosSaleOrderStatus.Cancelled;
                order.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync(ct);
            }
        }

        logger.LogInformation(
            "ViettelPost status {Tracking} code={Code} name={Name} → {Status} ({Rows} row)",
            orderSnapshot.DeliveryTrackingCode ?? orderSnapshot.DeliveryCarrierOrderId,
            statusCode, statusName, newStatus, rows);
    }

    ViettelPostShippingClient? ViettelClient() =>
        Resolve(ShippingCarrierCodes.ViettelPost) as ViettelPostShippingClient;

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

    public async Task<bool> ValidateViettelPostWebhookAuthAsync(
        string? authorization, string? bodyToken, string? trackingCode, CancellationToken ct)
    {
        var secrets = await db.PosShippingCarrierSettings.AsNoTracking()
            .Where(x => x.CarrierCode == ShippingCarrierCodes.ViettelPost
                        && x.Deleted == null && x.Enabled
                        && x.ExtraJson != null && x.ExtraJson != "")
            .Select(x => x.ExtraJson!)
            .ToListAsync(ct);

        var configured = secrets
            .Select(ViettelPostExtraJson.GetWebhookSecret)
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct(StringComparer.Ordinal)
            .ToList();

        if (configured.Count == 0) return true;

        if (!string.IsNullOrWhiteSpace(trackingCode))
        {
            var t = trackingCode.Trim();
            var order = await db.PosSaleOrders.AsNoTracking()
                .Where(o => o.Deleted == null && o.IsDelivery
                            && (o.DeliveryTrackingCode == t || o.DeliveryCarrierOrderId == t))
                .Select(o => new { o.StoreId })
                .FirstOrDefaultAsync(ct);
            if (order != null)
            {
                var storeSecret = await db.PosShippingCarrierSettings.AsNoTracking()
                    .Where(x => x.StoreId == order.StoreId
                                && x.CarrierCode == ShippingCarrierCodes.ViettelPost
                                && x.Deleted == null)
                    .Select(x => x.ExtraJson)
                    .FirstOrDefaultAsync(ct);
                var one = ViettelPostExtraJson.GetWebhookSecret(storeSecret);
                if (!string.IsNullOrWhiteSpace(one))
                    return ViettelPostExtraJson.MatchesWebhookAuth(one, authorization, bodyToken);
            }
        }

        return configured.Any(s =>
            ViettelPostExtraJson.MatchesWebhookAuth(s, authorization, bodyToken));
    }

    public async Task<bool> ValidateGhtkWebhookHashAsync(
        string? queryHash, string? labelId, string? partnerId, CancellationToken ct)
    {
        var secrets = await db.PosShippingCarrierSettings.AsNoTracking()
            .Where(x => x.CarrierCode == ShippingCarrierCodes.Ghtk
                        && x.Deleted == null && x.Enabled
                        && x.ExtraJson != null && x.ExtraJson != "")
            .Select(x => x.ExtraJson!)
            .ToListAsync(ct);

        var configured = secrets
            .Select(GhtkExtraJson.GetWebhookSecret)
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct(StringComparer.Ordinal)
            .ToList();

        if (configured.Count == 0) return true;

        Guid? storeId = null;
        if (!string.IsNullOrWhiteSpace(labelId) || !string.IsNullOrWhiteSpace(partnerId))
        {
            var label = (labelId ?? "").Trim();
            var partner = (partnerId ?? "").Trim();
            var order = await db.PosSaleOrders.AsNoTracking()
                .Where(o => o.Deleted == null && o.IsDelivery && (
                    (!string.IsNullOrEmpty(label) &&
                     (o.DeliveryTrackingCode == label || o.DeliveryCarrierOrderId == label))
                    || (!string.IsNullOrEmpty(partner) && o.OrderNo == partner)))
                .Select(o => new { o.StoreId })
                .FirstOrDefaultAsync(ct);
            storeId = order?.StoreId;
        }

        if (storeId != null)
        {
            var storeSecret = await db.PosShippingCarrierSettings.AsNoTracking()
                .Where(x => x.StoreId == storeId
                            && x.CarrierCode == ShippingCarrierCodes.Ghtk
                            && x.Deleted == null)
                .Select(x => x.ExtraJson)
                .FirstOrDefaultAsync(ct);
            var one = GhtkExtraJson.GetWebhookSecret(storeSecret);
            if (!string.IsNullOrWhiteSpace(one))
                return GhtkExtraJson.MatchesHash(one, queryHash);
        }

        return configured.Any(s => GhtkExtraJson.MatchesHash(s, queryHash));
    }

    public async Task<bool> ApplyGhtkWebhookAsync(
        string? labelId, string? partnerId, int? statusId, string? reasonOrText, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(labelId) && string.IsNullOrWhiteSpace(partnerId))
            return false;

        var label = (labelId ?? "").Trim();
        var partner = (partnerId ?? "").Trim();
        var order = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.Deleted == null && o.IsDelivery && (
                (!string.IsNullOrEmpty(label) &&
                 (o.DeliveryTrackingCode == label || o.DeliveryCarrierOrderId == label))
                || (!string.IsNullOrEmpty(partner) && o.OrderNo == partner)))
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);
        if (order == null) return false;

        var isOnline = string.Equals(order.SalesChannel, QrOnlineOrderStatuses.Channel,
            StringComparison.OrdinalIgnoreCase);
        var mapped = GhtkWebhookHelper.MapOnlineStatus(statusId);
        var labelStatus = !string.IsNullOrWhiteSpace(reasonOrText) && statusId == null
            ? reasonOrText.Trim()
            : GhtkWebhookHelper.StatusLabel(statusId);

        string newStatus;
        if (isOnline && mapped != null)
        {
            var prev = QrOnlineOrderStatuses.Normalize(order.DeliveryStatus);
            if (QrOnlineOrderStatuses.IsTerminal(prev) && mapped != prev)
            {
                logger.LogInformation(
                    "GHTK status skip terminal {OrderNo} {Prev} → {Next}",
                    order.OrderNo, prev, mapped);
                return true;
            }
            newStatus = mapped;
        }
        else
            newStatus = labelStatus;

        var now = DateTime.UtcNow;
        var rows = await db.PosSaleOrders.Where(o => o.Id == order.Id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryStatus, newStatus)
                .SetProperty(o => o.UpdatedAt, now)
                .SetProperty(o => o.DeliveryCarrierCode,
                    o => string.IsNullOrWhiteSpace(o.DeliveryCarrierCode)
                        ? ShippingCarrierCodes.Ghtk
                        : o.DeliveryCarrierCode)
                .SetProperty(o => o.DeliveryTrackingCode,
                    o => string.IsNullOrWhiteSpace(o.DeliveryTrackingCode) && !string.IsNullOrEmpty(label)
                        ? label
                        : o.DeliveryTrackingCode)
                .SetProperty(o => o.DeliveryDate,
                    o => newStatus == QrOnlineOrderStatuses.Delivered
                         || newStatus.Contains("Đã giao", StringComparison.OrdinalIgnoreCase)
                        ? (o.DeliveryDate ?? now)
                        : o.DeliveryDate), ct);

        logger.LogInformation("GHTK webhook {Label}/{Partner} status {StatusId} → {Status} ({Rows})",
            label, partner, statusId, newStatus, rows);

        if (isOnline && mapped == QrOnlineOrderStatuses.Cancelled
            && order.Status == PosSaleOrderStatus.Draft)
        {
            await db.PosSaleOrders.Where(o => o.Id == order.Id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(o => o.Status, PosSaleOrderStatus.Cancelled), ct);
        }
        else if (isOnline && mapped == QrOnlineOrderStatuses.Cancelled
                 && order.Status == PosSaleOrderStatus.Completed)
        {
            var tracked = await db.PosSaleOrders.AsTracking()
                .Include(o => o.Lines)
                .FirstOrDefaultAsync(o => o.Id == order.Id && o.Deleted == null, ct);
            if (tracked != null && tracked.Status == PosSaleOrderStatus.Completed)
            {
                var stockFullyReversed =
                    await PosSaleStockHelper.IsSaleStockFullyReversedAsync(db, tracked.StoreId, tracked);
                if (!stockFullyReversed)
                    await PosSaleStockHelper.ReverseSaleOrderAsync(
                        db, tracked.StoreId, tracked, "shipping-webhook");
                await PosSaleStockHelper.ReverseCustomerOnSaleCancelAsync(db, tracked.StoreId, tracked);
                await PosCustomerFinanceHelper.ReversePointsOnSaleCancelAsync(
                    db, tracked.StoreId, tracked, "shipping-webhook");
                await PosFinanceSyncHelper.ReverseSaleOnCancelAsync(db, tracked);
                await PosSaleWarrantyHelper.VoidOrderAsync(
                    db, tracked.StoreId, tracked.Id, "shipping-webhook");
                tracked.Status = PosSaleOrderStatus.Cancelled;
                tracked.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync(ct);
            }
        }

        return rows > 0;
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
        if (string.IsNullOrWhiteSpace(order.DeliveryTrackingCode))
            return new(false, order.DeliveryCarrierCode ?? "", Message: "Đơn chưa có mã vận đơn");

        var code = ShippingCarrierCodes.Normalize(order.DeliveryCarrierCode ?? "");
        if (!string.Equals(code, ShippingCarrierCodes.ViettelPost, StringComparison.OrdinalIgnoreCase))
            return new(false, code, Message: "Chỉ hỗ trợ hủy vận đơn Viettel Post qua API");

        var (settings, err) = await GetEnabledSettingsAsync(storeId, code, ct);
        if (settings == null)
            return new(false, code, Message: err);

        var client = ViettelClient();
        if (client == null)
            return new(false, code, Message: "Adapter chưa đăng ký");

        var result = await client.UpdateOrderStatusAsync(
            settings, order.DeliveryTrackingCode!, type: 4, note, ct);
        if (!result.Success) return result;

        var cancelStatus = QrOnlineOrderStatuses.Label(QrOnlineOrderStatuses.Cancelled);
        await db.PosSaleOrders.Where(o => o.Id == order.Id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryStatus, cancelStatus)
                .SetProperty(o => o.UpdatedAt, DateTime.UtcNow)
                .SetProperty(o => o.UpdatedBy, userEmail), ct);
        return result;
    }

    public async Task<ShippingTrackingResult> SyncTrackingAsync(
        Guid storeId, Guid orderId, string? userEmail, CancellationToken ct)
    {
        var order = await FindDeliveryOrderAsync(storeId, orderId, ct);
        if (order == null)
            return new(false, "", Message: "Không tìm thấy đơn giao hàng");
        if (string.IsNullOrWhiteSpace(order.DeliveryTrackingCode))
            return new(false, order.DeliveryCarrierCode ?? "", Message: "Đơn chưa có mã vận đơn");

        var code = ShippingCarrierCodes.Normalize(order.DeliveryCarrierCode ?? "");
        if (!string.Equals(code, ShippingCarrierCodes.ViettelPost, StringComparison.OrdinalIgnoreCase))
            return new(false, code, Message: "Chỉ hỗ trợ đồng bộ hành trình Viettel Post");

        var (settings, err) = await GetEnabledSettingsAsync(storeId, code, ct);
        if (settings == null)
            return new(false, code, Message: err);

        var client = ViettelClient();
        if (client == null)
            return new(false, code, Message: "Adapter chưa đăng ký");

        var tracking = await client.GetTrackingAsync(settings, order.DeliveryTrackingCode!, ct);
        if (!tracking.Success) return tracking;

        await ApplyViettelPostStatusToOrderAsync(
            order.Id, order, tracking.StatusCode, tracking.StatusName, ct);
        return tracking;
    }
}
