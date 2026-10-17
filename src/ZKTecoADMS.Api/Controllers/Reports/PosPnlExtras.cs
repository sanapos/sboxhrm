using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Services.Assets;
using ZKTecoADMS.Api.Services.Shipping;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Các khoản lãi / lỗ ngoài doanh thu thuần, dùng chung cho Kết quả kinh doanh và báo cáo Chi nhánh
/// (doanh thu thuần giữ nguyên = Σ Total):
/// <list type="bullet">
/// <item>Phụ thu, phí giao hàng thu khách (đơn hoàn thành) − cước hãng tính cho shop (gồm cước hoàn) — cùng quy tắc
/// báo cáo Vận chuyển: khách trả cước thẳng cho hãng thì shop không thu, không chi; vận đơn hủy trước lấy hàng không tốn cước.
/// Đơn hoàn / giao thất bại (đơn có thể đã hủy) vẫn mất cước.</item>
/// <item>Khấu hao tài sản trong kỳ (đường thẳng theo tỷ lệ %/năm), gán chi nhánh theo nhân viên đang giữ, chưa giao = trụ sở.</item>
/// <item>Cọc khách bỏ = phiếu thu cọc đã chuyển sang danh mục «Mất cọc đặt chỗ» khi khách hủy / không đến.</item>
/// </list>
/// </summary>
internal static class PosPnlExtras
{
    public const string ForfeitedDepositCategory = "Mất cọc đặt chỗ";

    /// <summary>Phiếu chi mua tài sản: không tính chi phí trong kỳ (đã vào khấu hao từng tháng).</summary>
    public const string AssetPurchaseCategory = "Mua tài sản";

    public sealed record ShipRow(Guid Branch, decimal Surcharge, decimal DeliveryFee, decimal CarrierCost);

    /// <summary>
    /// Phụ thu / phí giao hàng / cước hãng theo chi nhánh. <paramref name="ordersInPeriod"/>: đơn của cửa hàng trong kỳ
    /// (theo ngày bán), MỌI trạng thái — đã lọc chi nhánh / người xem.
    /// </summary>
    public static async Task<List<ShipRow>> ShippingRowsAsync(IQueryable<PosSaleOrder> ordersInPeriod, Guid hq)
    {
        var rows = await ordersInPeriod
            .Where(o => o.Status == PosSaleOrderStatus.Completed
                        || (o.DeliveryCarrierCode != null && o.DeliveryCarrierCode != ""))
            .Select(o => new
            {
                B = o.BranchId ?? hq,
                Done = o.Status == PosSaleOrderStatus.Completed,
                o.SurchargeAmount,
                o.DeliveryFee,
                Carrier = o.DeliveryCarrierCode != null && o.DeliveryCarrierCode != "",
                CustomerPays = o.DeliveryFeePayer == ShippingFeePayer.Customer,
                ShipCancelled = o.DeliveryStatusCode == ShipmentStatus.Cancelled,
                Fee = (o.DeliveryCarrierFee ?? 0) + (o.DeliveryReturnFee ?? 0),
            })
            .ToListAsync();
        return rows.Select(r => new ShipRow(
                r.B,
                r.Done ? Math.Max(0, r.SurchargeAmount) : 0,
                r.Done && !r.CustomerPays ? Math.Max(0, r.DeliveryFee) : 0,
                r.Carrier && !r.CustomerPays && !r.ShipCancelled ? Math.Max(0, r.Fee) : 0))
            .ToList();
    }

    /// <summary>Khấu hao trong kỳ [fromUtc, toUtc) theo chi nhánh (nhân viên giữ → chi nhánh của NV; chưa giao → trụ sở).</summary>
    public static async Task<Dictionary<Guid, decimal>> DepreciationByBranchAsync(
        ZKTecoDbContext db, Guid storeId, DateTime fromUtc, DateTime toUtc, Guid hq)
    {
        var assets = await db.Assets.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.IsActive && a.DepreciationRate > 0 && a.PurchaseDate != null
                        && a.PurchaseDate < toUtc && a.PurchasePrice > 0
                        && a.Status != AssetStatus.Disposed && a.Status != AssetStatus.Lost)
            .Select(a => new
            {
                Asset = a,
                Branch = a.CurrentAssignee != null ? a.CurrentAssignee.BranchId : null,
            })
            .ToListAsync();
        var result = new Dictionary<Guid, decimal>();
        foreach (var x in assets)
        {
            var dep = AssetValuation.PeriodDepreciation(x.Asset, fromUtc, toUtc);
            if (dep == 0) continue;
            var b = x.Branch ?? hq;
            result[b] = result.GetValueOrDefault(b) + dep;
        }
        return result;
    }
}
