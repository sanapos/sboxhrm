using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Infrastructure.Services;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>
/// Vòng đời vận đơn thống nhất mọi hãng: trạng thái chuẩn, nhật ký, xác thực webhook,
/// hoàn hàng (chỉ nhập kho lại khi hàng đã về shop), đối soát COD.
/// </summary>
public partial class PosShippingService
{
    // ── Xác thực webhook ──────────────────────────────────────────────

    /// <summary>Mã bí mật webhook của cửa hàng cho hãng (tự sinh nếu chưa có).</summary>
    public async Task<string?> EnsureWebhookSecretAsync(Guid storeId, string carrierCode, CancellationToken ct)
    {
        var code = ShippingCarrierCodes.Normalize(carrierCode);
        var row = await db.PosShippingCarrierSettings.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.CarrierCode == code && x.Deleted == null, ct);
        if (row == null) return null;
        var secret = ViettelPostExtraJson.GetWebhookSecret(row.ExtraJson);
        if (!string.IsNullOrWhiteSpace(secret) && !IsWeakWebhookSecret(secret)) return secret;
        secret = Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();
        row.ExtraJson = ViettelPostExtraJson.MergeWebhookSecret(row.ExtraJson, secret);
        row.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Generated shipping webhook secret for store {StoreId} {Carrier}", storeId, code);
        return secret;
    }

    /// <summary>
    /// Mã quá ngắn hoặc là mã mẫu từng in sẵn trong app (ai cũng biết) → coi như chưa có, tự đổi mã ngẫu nhiên.
    /// </summary>
    public static bool IsWeakWebhookSecret(string secret)
    {
        var t = secret.Trim();
        return t.Length < 16
               || t.Equals("SboxGhtk2026", StringComparison.OrdinalIgnoreCase)
               || t.Equals("SboxVtp2026!", StringComparison.OrdinalIgnoreCase);
    }

    static bool SecretEquals(string secret, string? provided)
    {
        if (string.IsNullOrWhiteSpace(provided)) return false;
        var a = Encoding.UTF8.GetBytes(secret.Trim());
        var b = Encoding.UTF8.GetBytes(provided.Trim());
        return a.Length == b.Length && CryptographicOperations.FixedTimeEquals(a, b);
    }

    /// <summary>
    /// Webhook chỉ được nhận khi mã bí mật khớp đúng cửa hàng sở hữu vận đơn.
    /// Chưa cấu hình mã → tự sinh và TỪ CHỐI (chủ shop dán link webhook mới ở hãng).
    /// </summary>
    public async Task<bool> AuthorizeWebhookAsync(
        string carrierCode, string? trackingCode, string? orderNo, string? providedSecret,
        string? authorizationHeader, CancellationToken ct)
    {
        var order = await FindOrderByTrackingAsync(trackingCode, orderNo, ct);
        if (order == null) return false;
        var secret = await EnsureWebhookSecretAsync(order.StoreId, carrierCode, ct);
        if (string.IsNullOrWhiteSpace(secret)) return false;
        if (SecretEquals(secret, providedSecret)) return true;
        // Viettel Post gửi token qua header Authorization.
        if (!string.IsNullOrWhiteSpace(authorizationHeader))
        {
            var auth = authorizationHeader.Trim();
            if (auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) auth = auth[7..].Trim();
            if (SecretEquals(secret, auth)) return true;
        }
        logger.LogWarning("Shipping webhook {Carrier} rejected — secret mismatch for {Tracking}",
            carrierCode, trackingCode ?? orderNo);
        return false;
    }

    async Task<PosSaleOrder?> FindOrderByTrackingAsync(string? trackingCode, string? orderNo, CancellationToken ct)
    {
        var t = (trackingCode ?? "").Trim();
        var no = (orderNo ?? "").Trim();
        if (t.Length == 0 && no.Length == 0) return null;
        return await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.Deleted == null && o.IsDelivery && (
                (t.Length > 0 && (o.DeliveryTrackingCode == t || o.DeliveryCarrierOrderId == t))
                || (no.Length > 0 && o.OrderNo == no)))
            .OrderByDescending(o => o.CreatedAt)
            .FirstOrDefaultAsync(ct);
    }

    // ── Cập nhật trạng thái chuẩn ─────────────────────────────────────

    /// <summary>
    /// Áp trạng thái vận đơn cho đơn. <paramref name="code"/> null = hãng gửi trạng thái chưa quy đổi
    /// được (chỉ ghi nhãn cho đơn tại quầy). Trả false nếu không tìm thấy đơn.
    /// </summary>
    public async Task<bool> ApplyShipmentStatusAsync(
        Guid orderId, string carrierCode, string? code, string? rawStatus, string? reason,
        string source, string? userEmail, CancellationToken ct, DateTime? occurredAt = null)
    {
        var order = await db.PosSaleOrders.AsNoTracking()
            .FirstOrDefaultAsync(o => o.Id == orderId && o.Deleted == null, ct);
        if (order == null) return false;

        var now = DateTime.UtcNow;
        var at = occurredAt ?? now;
        var carrier = ShippingCarrierCodes.Normalize(carrierCode);
        var isOnline = string.Equals(order.SalesChannel, QrOnlineOrderStatuses.Channel,
            StringComparison.OrdinalIgnoreCase);
        var safeReason = string.IsNullOrWhiteSpace(reason) ? null : Trim(reason, 500);

        if (code == null)
        {
            if (!isOnline && !string.IsNullOrWhiteSpace(rawStatus))
            {
                await db.PosSaleOrders.Where(o => o.Id == orderId)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(o => o.DeliveryStatus, Trim(rawStatus, 200))
                        .SetProperty(o => o.UpdatedAt, now), ct);
            }
            return true;
        }

        var prev = order.DeliveryStatusCode;
        if (!ShipmentStatus.CanTransition(prev, code))
        {
            logger.LogInformation("Shipment {OrderNo} skip {Prev} → {Next} (terminal)", order.OrderNo, prev, code);
            return true;
        }

        var isNew = prev != code;
        var display = isOnline
            ? ShipmentStatus.ToOnlineStatus(code) ?? order.DeliveryStatus
            : ShipmentStatus.Label(code);
        var picked = code is ShipmentStatus.InTransit or ShipmentStatus.Delivering;
        var delivered = code == ShipmentStatus.Delivered;
        var failedNow = isNew && code == ShipmentStatus.DeliveryFailed;
        var keepReason = code is ShipmentStatus.DeliveryFailed or ShipmentStatus.Returning
            or ShipmentStatus.Returned or ShipmentStatus.Cancelled or ShipmentStatus.Issue;

        await db.PosSaleOrders.Where(o => o.Id == orderId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryStatusCode, code)
                .SetProperty(o => o.DeliveryStatusAt, at)
                .SetProperty(o => o.DeliveryStatus, display)
                .SetProperty(o => o.DeliveryCarrierCode,
                    o => string.IsNullOrWhiteSpace(o.DeliveryCarrierCode) ? carrier : o.DeliveryCarrierCode)
                .SetProperty(o => o.DeliveryPickedAt, o => picked && o.DeliveryPickedAt == null ? at : o.DeliveryPickedAt)
                .SetProperty(o => o.DeliveryDeliveredAt, o => delivered ? (o.DeliveryDeliveredAt ?? at) : o.DeliveryDeliveredAt)
                .SetProperty(o => o.DeliveryDate, o => delivered ? (o.DeliveryDate ?? at) : o.DeliveryDate)
                .SetProperty(o => o.DeliveryFailCount, o => failedNow ? o.DeliveryFailCount + 1 : o.DeliveryFailCount)
                .SetProperty(o => o.DeliveryLastReason, o => keepReason && safeReason != null ? safeReason : o.DeliveryLastReason)
                .SetProperty(o => o.DeliveryReturnedAt,
                    o => code == ShipmentStatus.Returned ? (o.DeliveryReturnedAt ?? at) : o.DeliveryReturnedAt)
                .SetProperty(o => o.DeliveryCancelledAt,
                    o => code == ShipmentStatus.Cancelled ? (o.DeliveryCancelledAt ?? at) : o.DeliveryCancelledAt)
                .SetProperty(o => o.UpdatedAt, now)
                .SetProperty(o => o.UpdatedBy, o => userEmail ?? o.UpdatedBy), ct);

        if (isNew || safeReason != null)
        {
            db.PosShipmentEvents.Add(new PosShipmentEvent
            {
                Id = Guid.NewGuid(),
                StoreId = order.StoreId,
                SaleOrderId = order.Id,
                CarrierCode = carrier,
                TrackingCode = order.DeliveryTrackingCode,
                StatusCode = code,
                RawStatus = rawStatus == null ? null : Trim(rawStatus, 200),
                Reason = safeReason,
                Source = Trim(source, 20),
                OccurredAt = at,
                IsActive = true,
                CreatedAt = now,
                CreatedBy = userEmail,
            });
            await db.SaveChangesAsync(ct);
        }

        if (!isNew) return true;

        // Hàng đã về shop → mới nhập kho lại / trừ doanh thu (cả đơn online và đơn tại quầy).
        if (code == ShipmentStatus.Returned)
            await ReverseSaleForShipmentAsync(orderId, "shipping-returned", ct);
        // Hủy vận đơn: đơn online = khách hủy → hủy đơn. Đơn tại quầy: shop có thể giao lại hãng khác.
        else if (code == ShipmentStatus.Cancelled && isOnline)
            await ReverseSaleForShipmentAsync(orderId, "shipping-cancelled", ct);

        logger.LogInformation("Shipment {OrderNo} {Carrier} {Prev} → {Next} ({Source})",
            order.OrderNo, carrier, prev, code, source);
        return true;
    }

    /// <summary>Hủy đơn bán do vận chuyển: đơn tạm → Hủy; đơn đã bán → hoàn kho, công nợ, điểm, sổ quỹ.</summary>
    async Task ReverseSaleForShipmentAsync(Guid orderId, string reason, CancellationToken ct)
    {
        var order = await db.PosSaleOrders.AsTracking()
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == orderId && o.Deleted == null, ct);
        if (order == null) return;
        if (order.Status == PosSaleOrderStatus.Draft)
        {
            order.Status = PosSaleOrderStatus.Cancelled;
            order.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync(ct);
            return;
        }
        if (order.Status != PosSaleOrderStatus.Completed) return;

        var stockFullyReversed = await PosSaleStockHelper.IsSaleStockFullyReversedAsync(db, order.StoreId, order);
        if (!stockFullyReversed)
            await PosSaleStockHelper.ReverseSaleOrderAsync(db, order.StoreId, order, reason);
        await PosSaleStockHelper.ReverseCustomerOnSaleCancelAsync(db, order.StoreId, order);
        await PosCustomerFinanceHelper.ReversePointsOnSaleCancelAsync(db, order.StoreId, order, reason);
        await PosFinanceSyncHelper.ReverseSaleOnCancelAsync(db, order);
        await PosSaleWarrantyHelper.VoidOrderAsync(db, order.StoreId, order.Id, reason);
        order.Status = PosSaleOrderStatus.Cancelled;
        order.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    /// <summary>
    /// Shop xác nhận đã nhận lại hàng hoàn (hãng không báo / báo trễ). Nhập kho lại + hủy đơn
    /// nếu chưa làm, ghi người xác nhận.
    /// </summary>
    public async Task<(bool Ok, string Message)> ConfirmReturnReceivedAsync(
        Guid storeId, Guid orderId, string? note, string? userEmail, CancellationToken ct)
    {
        var order = await FindDeliveryOrderAsync(storeId, orderId, ct);
        if (order == null) return (false, "Không tìm thấy đơn giao hàng");
        if (order.DeliveryReturnReceivedAt != null)
            return (true, "Đơn đã xác nhận nhận hàng hoàn trước đó");
        if (order.DeliveryStatusCode == ShipmentStatus.Delivered)
            return (false, "Đơn đang ở trạng thái Đã giao — dùng Trả hàng bán nếu khách trả lại");

        var carrier = order.DeliveryCarrierCode ?? "Internal";
        if (order.DeliveryStatusCode != ShipmentStatus.Returned)
            await ApplyShipmentStatusAsync(order.Id, carrier, ShipmentStatus.Returned, "manual",
                string.IsNullOrWhiteSpace(note) ? "Shop xác nhận đã nhận hàng hoàn" : note,
                "manual", userEmail, ct);
        var now = DateTime.UtcNow;
        await db.PosSaleOrders.Where(o => o.Id == order.Id)
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryReturnReceivedAt, now)
                .SetProperty(o => o.DeliveryReturnReceivedBy, userEmail)
                .SetProperty(o => o.UpdatedAt, now), ct);
        return (true, "Đã xác nhận nhận hàng hoàn — hàng đã nhập lại kho");
    }

    /// <summary>Đánh dấu hãng đã chuyển tiền COD cho các đơn (đối soát).</summary>
    public async Task<int> MarkCodSettledAsync(
        Guid storeId, IReadOnlyList<Guid> orderIds, bool settled, string? userEmail, CancellationToken ct)
    {
        if (orderIds.Count == 0) return 0;
        var now = DateTime.UtcNow;
        return await db.PosSaleOrders
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsDelivery
                        && orderIds.Contains(o.Id))
            .ExecuteUpdateAsync(s => s
                .SetProperty(o => o.DeliveryCodSettledAt, settled ? now : null)
                .SetProperty(o => o.UpdatedAt, now)
                .SetProperty(o => o.UpdatedBy, userEmail), ct);
    }

    public async Task<List<object>> ListEventsAsync(Guid storeId, Guid orderId, CancellationToken ct)
    {
        var rows = await db.PosShipmentEvents.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.SaleOrderId == orderId && e.Deleted == null)
            .OrderBy(e => e.OccurredAt)
            .ToListAsync(ct);
        return rows.Select(e => (object)new
        {
            statusCode = e.StatusCode,
            label = ShipmentStatus.Label(e.StatusCode),
            rawStatus = e.RawStatus,
            reason = e.Reason,
            source = e.Source,
            carrierCode = e.CarrierCode,
            trackingCode = e.TrackingCode,
            occurredAt = e.OccurredAt,
        }).ToList();
    }

    static string Trim(string s, int max)
    {
        var t = s.Trim();
        return t.Length > max ? t[..max] : t;
    }
}
