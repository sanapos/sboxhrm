using System.Data;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services.Shipping;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Services;

/// <summary>Thanh toán COD / giao nội bộ / vận đơn cho đơn QR online.</summary>
public static class PosOnlineOrderHelper
{
    public const string InternalCarrierCode = "Internal";
    public const string InternalCarrierName = "Giao hàng nội bộ";
    public const string QrOnlineChannel = "QR online";

    public static bool IsInternalCarrier(string? code) =>
        string.Equals(code?.Trim(), InternalCarrierCode, StringComparison.OrdinalIgnoreCase)
        || string.Equals(code?.Trim(), "noibo", StringComparison.OrdinalIgnoreCase);

    public static bool IsQrOnlineOrder(PosSaleOrder order) =>
        string.Equals(order.SalesChannel, QrOnlineChannel, StringComparison.OrdinalIgnoreCase);

    public static bool IsWalkInCustomerName(string? name)
    {
        var t = (name ?? "").Trim();
        return t.Length == 0
               || t.Equals("Bán cho người tiêu dùng", StringComparison.OrdinalIgnoreCase)
               || t.Equals("Người tiêu dùng", StringComparison.OrdinalIgnoreCase);
    }

    public readonly record struct GuestMetaSnapshot(
        string? CustomerName,
        string? DeliveryPhone,
        string? DeliveryAddress,
        string? DeliveryProvince,
        string? DeliveryDistrict,
        string? DeliveryWard,
        string? DeliveryPartner,
        string? DeliveryStatus,
        bool IsDelivery);

    public static GuestMetaSnapshot CaptureGuestMeta(PosSaleOrder order) => new(
        order.CustomerName,
        order.DeliveryPhone,
        order.DeliveryAddress,
        order.DeliveryProvince,
        order.DeliveryDistrict,
        order.DeliveryWard,
        order.DeliveryPartner,
        order.DeliveryStatus,
        order.IsDelivery);

    /// <summary>POS thanh toán online — giữ tên/SĐT/địa chỉ khách đặt nếu client gửi walk-in hoặc thiếu field giao.</summary>
    public static void RestoreGuestMetaAfterDraftDto(
        PosSaleOrder order, GuestMetaSnapshot prev, string? dtoCustomerName,
        string? dtoDeliveryPhone, string? dtoDeliveryAddress, bool dtoIsDelivery)
    {
        if (!IsQrOnlineOrder(order)) return;

        order.SalesChannel = QrOnlineChannel;
        order.IsDelivery = true;

        if (IsWalkInCustomerName(dtoCustomerName) && !IsWalkInCustomerName(prev.CustomerName))
            order.CustomerName = prev.CustomerName;
        else if (!IsWalkInCustomerName(dtoCustomerName))
            order.CustomerName = dtoCustomerName!.Trim();

        if (string.IsNullOrWhiteSpace(dtoDeliveryPhone) && !string.IsNullOrWhiteSpace(prev.DeliveryPhone))
            order.DeliveryPhone = prev.DeliveryPhone;
        if (string.IsNullOrWhiteSpace(dtoDeliveryAddress) && !string.IsNullOrWhiteSpace(prev.DeliveryAddress))
            order.DeliveryAddress = prev.DeliveryAddress;
        if (string.IsNullOrWhiteSpace(order.DeliveryProvince) && !string.IsNullOrWhiteSpace(prev.DeliveryProvince))
            order.DeliveryProvince = prev.DeliveryProvince;
        if (string.IsNullOrWhiteSpace(order.DeliveryDistrict) && !string.IsNullOrWhiteSpace(prev.DeliveryDistrict))
            order.DeliveryDistrict = prev.DeliveryDistrict;
        if (string.IsNullOrWhiteSpace(order.DeliveryWard) && !string.IsNullOrWhiteSpace(prev.DeliveryWard))
            order.DeliveryWard = prev.DeliveryWard;
        if (string.IsNullOrWhiteSpace(order.DeliveryPartner) && !string.IsNullOrWhiteSpace(prev.DeliveryPartner))
            order.DeliveryPartner = prev.DeliveryPartner;

        if (!dtoIsDelivery && prev.IsDelivery)
            order.IsDelivery = true;

        if (string.IsNullOrWhiteSpace(order.DeliveryStatus) && !string.IsNullOrWhiteSpace(prev.DeliveryStatus))
            order.DeliveryStatus = prev.DeliveryStatus;
    }

    /// <summary>Hoàn thành đơn online (COD — thu khi giao, PaidAmount=0).</summary>
    public static async Task<(bool Ok, string? Error)> TryCompleteAsCodAsync(
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        string? userEmail,
        CancellationToken ct = default)
    {
        if (order.Status == PosSaleOrderStatus.Completed)
            return (true, null);
        if (order.Status != PosSaleOrderStatus.Draft)
            return (false, "Đơn không ở trạng thái tạm");
        if (order.Lines.Count(l => l.Deleted == null) == 0)
            return (false, "Đơn trống");

        var allowNeg = await db.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => s.AllowNegativeStock)
            .FirstOrDefaultAsync(ct);

        PosDraftLockHelper.Release(order);
        order.Status = PosSaleOrderStatus.Completed;
        order.SaleDate = DateTime.UtcNow;
        order.SoldBy ??= userEmail;
        order.PaymentMethod = "COD";
        order.PaidAmount = 0;
        if (PosSaleStockHelper.NeedsOfficialOrderNo(order.OrderNo))
            order.OrderNo = await PosSaleStockHelper.NextOrderNoAsync(db, storeId, order.SaleDate);
        order.InvoiceSlot = null;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = userEmail;

        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, ct);
        try
        {
            await PosSaleStockHelper.EnsureLineUnitIdsAsync(db, order.Lines);
            var lineInputs = order.Lines
                .Where(l => l.Deleted == null)
                .Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson))
                .ToList();
            var (plan, stockErr) = await PosSaleStockHelper.PrepareSaleStockAsync(
                db, storeId, PosSaleStockHelper.ExpandStockInputsWithToppings(lineInputs),
                allowNegativeStock: allowNeg);
            if (stockErr != null)
            {
                await tx.RollbackAsync(ct);
                return (false, stockErr);
            }

            await PosSaleStockHelper.ApplySaleStockAsync(
                db, storeId, order, order.Lines.Where(l => l.Deleted == null).ToList(),
                plan!, userEmail);
            await PosSaleStockHelper.UpdateCustomerOnSaleCompleteAsync(db, storeId, order);
            await PosFinanceSyncHelper.SyncSaleOnCompleteAsync(db, order, Guid.Empty);
            PosKitchenKdsHelper.CloseOpenOnPaid(order.Lines);
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return (true, null);
        }
        catch
        {
            await tx.RollbackAsync(ct);
            throw;
        }
    }

    public static void MarkInternalDelivery(PosSaleOrder order, string? userEmail)
    {
        order.DeliveryCarrierCode = InternalCarrierCode;
        order.DeliveryPartner = InternalCarrierName;
        order.DeliveryStatus = QrOnlineOrderStatuses.Shipping;
        order.UpdatedAt = DateTime.UtcNow;
        order.UpdatedBy = userEmail;
    }

    public static async Task<(bool Ok, string? TrackingCode, string? Message)> TryCreateShipmentAsync(
        PosShippingService shipping,
        ZKTecoDbContext db,
        Guid storeId,
        PosSaleOrder order,
        string carrierCode,
        string? userEmail,
        CancellationToken ct = default,
        int? weightGrams = null,
        int? lengthCm = null,
        int? widthCm = null,
        int? heightCm = null,
        decimal? codAmount = null,
        string? serviceCode = null,
        string? note = null,
        string? shipFeePayer = null,
        decimal? fixedShipFee = null)
    {
        if (IsInternalCarrier(carrierCode))
        {
            MarkInternalDelivery(order, userEmail);
            await db.SaveChangesAsync(ct);
            return (true, null, InternalCarrierName);
        }

        var code = ShippingCarrierCodes.Normalize(carrierCode);
        var payer = ShippingFeePayer.Normalize(shipFeePayer);
        var cod = codAmount
                  ?? (order.Status == PosSaleOrderStatus.Completed ? 0m : order.PayableTotal);

        var package = await shipping.EstimatePackageForOrderAsync(
            storeId, order.Id, weightGrams, lengthCm, widthCm, heightCm, ct);

        string? resolvedService = serviceCode;
        if (string.IsNullOrWhiteSpace(resolvedService))
        {
            var quote = await shipping.QuoteAsync(storeId, new ShippingQuoteRequest(
                code,
                order.CustomerName ?? "Khách",
                order.DeliveryPhone ?? "",
                order.DeliveryAddress ?? "",
                order.DeliveryProvince,
                order.DeliveryDistrict,
                order.DeliveryWard,
                WeightGrams: package.ChargeableWeightGrams,
                CodAmount: cod,
                InsuranceValue: order.PayableTotal,
                LengthCm: package.LengthCm,
                WidthCm: package.WidthCm,
                HeightCm: package.HeightCm), ct);
            if (quote.Success && !string.IsNullOrWhiteSpace(quote.ServiceCode))
                resolvedService = quote.ServiceCode;
        }

        var result = await shipping.CreateForOrderAsync(storeId, new ShippingCreateRequest(
            carrierCode,
            order.Id,
            Note: note,
            WeightGrams: package.ChargeableWeightGrams,
            CodAmount: cod,
            ServiceCode: resolvedService,
            ToProvince: order.DeliveryProvince,
            ToDistrict: order.DeliveryDistrict,
            ToWard: order.DeliveryWard,
            LengthCm: package.LengthCm,
            WidthCm: package.WidthCm,
            HeightCm: package.HeightCm,
            ShipFeePayer: payer,
            FixedShipFee: fixedShipFee), userEmail, ct);
        if (!result.Success)
            return (false, result.TrackingCode, result.Message ?? "Không tạo được vận đơn");
        return (true, result.TrackingCode, result.Message ?? "Đã tạo vận đơn");
    }
}
