using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Api.Services.Shipping;

public record ShippingReportRow(
    Guid OrderId,
    string OrderNo,
    string? CustomerName,
    string? Phone,
    string? CarrierCode,
    string CarrierName,
    string? TrackingCode,
    string? ServiceName,
    string? StatusCode,
    string StatusLabel,
    decimal DeliveryFee,
    decimal? CarrierFee,
    string? FeePayer,
    decimal CodAmount,
    DateTime? ShippedAt,
    DateTime? StatusAt,
    DateTime? DeliveredAt,
    int FailCount,
    string? Reason,
    DateTime? ReturnedAt,
    DateTime? ReturnReceivedAt,
    DateTime? CancelledAt,
    DateTime? CodSettledAt,
    double? DeliveryHours);

public record ShippingReportCarrier(
    string CarrierCode,
    string CarrierName,
    int Shipments,
    int Delivered,
    int InProgress,
    int FailedOrders,
    int FailedAttempts,
    int Returning,
    int Returned,
    int Cancelled,
    double SuccessRate,
    double? AvgDeliveryHours,
    decimal FeeCharged,
    decimal CarrierCost,
    decimal ShipProfit,
    decimal CodDelivered,
    decimal CodPending);

public record ShippingReport(
    DateTime FromUtc,
    DateTime ToUtc,
    ShippingReportCarrier Total,
    IReadOnlyList<ShippingReportCarrier> ByCarrier,
    IReadOnlyList<ShippingReportRow> Failed,
    IReadOnlyList<ShippingReportRow> Returns,
    IReadOnlyList<ShippingReportRow> Cancelled,
    IReadOnlyList<ShippingReportRow> Cod,
    IReadOnlyList<ShippingReportRow> All);

public partial class PosShippingService
{
    /// <summary>
    /// Báo cáo vận chuyển theo ngày tạo vận đơn: theo hãng, giao thất bại, hoàn hàng,
    /// hủy vận đơn, đối soát COD, lãi/lỗ phí ship.
    /// </summary>
    public async Task<ShippingReport> BuildReportAsync(
        Guid storeId, DateTime? from, DateTime? to, string? carrier, CancellationToken ct)
    {
        // Ngày theo giờ Việt Nam (UTC+7).
        var toDay = (to ?? DateTime.UtcNow.AddHours(7)).Date;
        var fromDay = (from ?? toDay.AddDays(-29)).Date;
        if (fromDay > toDay) (fromDay, toDay) = (toDay, fromDay);
        var fromUtc = fromDay.AddHours(-7);
        var toUtc = toDay.AddDays(1).AddHours(-7);
        var carrierCode = string.IsNullOrWhiteSpace(carrier) ? null : ShippingCarrierCodes.Normalize(carrier);

        var q = db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsDelivery
                        && o.DeliveryCarrierCode != null && o.DeliveryCarrierCode != ""
                        && (o.DeliveryShippedAt ?? o.CreatedAt) >= fromUtc
                        && (o.DeliveryShippedAt ?? o.CreatedAt) < toUtc);
        if (carrierCode != null) q = q.Where(o => o.DeliveryCarrierCode == carrierCode);

        var rows = await q
            .OrderByDescending(o => o.DeliveryShippedAt ?? o.CreatedAt)
            .Select(o => new
            {
                o.Id, o.OrderNo, o.CustomerName, o.DeliveryPhone, o.DeliveryCarrierCode, o.DeliveryTrackingCode,
                o.DeliveryServiceName, o.DeliveryStatusCode, o.DeliveryStatus, o.DeliveryFee, o.DeliveryCarrierFee,
                o.DeliveryFeePayer, o.DeliveryCodAmount, o.DeliveryShippedAt, o.CreatedAt, o.DeliveryStatusAt,
                o.DeliveryDeliveredAt, o.DeliveryFailCount, o.DeliveryLastReason, o.DeliveryReturnedAt,
                o.DeliveryReturnReceivedAt, o.DeliveryCancelledAt, o.DeliveryCodSettledAt,
            })
            .Take(5000)
            .ToListAsync(ct);

        var list = rows.Select(o =>
        {
            var shipped = o.DeliveryShippedAt ?? o.CreatedAt;
            double? hours = o.DeliveryDeliveredAt != null
                ? Math.Round((o.DeliveryDeliveredAt.Value - shipped).TotalHours, 1)
                : null;
            var code = o.DeliveryStatusCode;
            return new ShippingReportRow(
                o.Id, o.OrderNo, o.CustomerName, o.DeliveryPhone, o.DeliveryCarrierCode,
                ShippingCarrierCodes.DisplayName(o.DeliveryCarrierCode ?? ""), o.DeliveryTrackingCode,
                o.DeliveryServiceName, code,
                string.IsNullOrWhiteSpace(code) ? (o.DeliveryStatus ?? "Chưa rõ") : ShipmentStatus.Label(code),
                o.DeliveryFee, o.DeliveryCarrierFee, o.DeliveryFeePayer, o.DeliveryCodAmount ?? 0,
                shipped, o.DeliveryStatusAt, o.DeliveryDeliveredAt, o.DeliveryFailCount, o.DeliveryLastReason,
                o.DeliveryReturnedAt, o.DeliveryReturnReceivedAt, o.DeliveryCancelledAt, o.DeliveryCodSettledAt,
                hours is > 0 ? hours : null);
        }).ToList();

        var byCarrier = list
            .GroupBy(r => r.CarrierCode ?? "")
            .Select(g => Summarize(g.Key, ShippingCarrierCodes.DisplayName(g.Key), g.ToList()))
            .OrderByDescending(c => c.Shipments)
            .ToList();

        return new ShippingReport(
            fromUtc, toUtc,
            Summarize("all", "Tất cả hãng", list),
            byCarrier,
            list.Where(r => r.FailCount > 0 || r.StatusCode == ShipmentStatus.DeliveryFailed).ToList(),
            list.Where(r => r.StatusCode is ShipmentStatus.Returning or ShipmentStatus.Returned).ToList(),
            list.Where(r => r.StatusCode == ShipmentStatus.Cancelled).ToList(),
            list.Where(r => r.CodAmount > 0 && r.StatusCode == ShipmentStatus.Delivered).ToList(),
            list);
    }

    /// <summary>Tổng hợp chỉ số cho một nhóm vận đơn (theo hãng hoặc toàn bộ).</summary>
    public static ShippingReportCarrier Summarize(string code, string name, IReadOnlyList<ShippingReportRow> g)
    {
        var delivered = g.Count(r => r.StatusCode == ShipmentStatus.Delivered);
        var returned = g.Count(r => r.StatusCode == ShipmentStatus.Returned);
        var cancelled = g.Count(r => r.StatusCode == ShipmentStatus.Cancelled);
        var returning = g.Count(r => r.StatusCode == ShipmentStatus.Returning);
        // Tỉ lệ thành công = đã giao / (đã giao + hoàn) — bỏ vận đơn hủy trước khi lấy hàng và đơn đang đi.
        var finished = delivered + returned;
        var hours = g.Where(r => r.DeliveryHours is > 0).Select(r => r.DeliveryHours!.Value).ToList();
        // Cước shop chịu: shop trả / phí cố định; khách trả trực tiếp cho hãng thì shop không tốn.
        var carrierCost = g.Where(r => r.StatusCode != ShipmentStatus.Cancelled && r.FeePayer != ShippingFeePayer.Customer)
            .Sum(r => r.CarrierFee ?? 0);
        var feeCharged = g.Where(r => r.StatusCode is not (ShipmentStatus.Cancelled or ShipmentStatus.Returned))
            .Sum(r => r.DeliveryFee);
        return new ShippingReportCarrier(
            code, name,
            Shipments: g.Count,
            Delivered: delivered,
            InProgress: g.Count(r => r.StatusCode is ShipmentStatus.Created or ShipmentStatus.Picking
                or ShipmentStatus.InTransit or ShipmentStatus.Delivering or ShipmentStatus.DeliveryFailed
                or ShipmentStatus.Creating or null),
            FailedOrders: g.Count(r => r.FailCount > 0 || r.StatusCode == ShipmentStatus.DeliveryFailed),
            FailedAttempts: g.Sum(r => Math.Max(r.FailCount, r.StatusCode == ShipmentStatus.DeliveryFailed ? 1 : 0)),
            Returning: returning,
            Returned: returned,
            Cancelled: cancelled,
            SuccessRate: finished == 0 ? 0 : Math.Round(100.0 * delivered / finished, 1),
            AvgDeliveryHours: hours.Count == 0 ? null : Math.Round(hours.Average(), 1),
            FeeCharged: feeCharged,
            CarrierCost: carrierCost,
            ShipProfit: feeCharged - carrierCost,
            CodDelivered: g.Where(r => r.StatusCode == ShipmentStatus.Delivered).Sum(r => r.CodAmount),
            CodPending: g.Where(r => r.StatusCode == ShipmentStatus.Delivered && r.CodSettledAt == null)
                .Sum(r => r.CodAmount));
    }
}
