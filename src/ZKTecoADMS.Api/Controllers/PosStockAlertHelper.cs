using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Một định nghĩa chung cho cảnh báo kho (Tổng quan, báo cáo, thông báo hằng ngày):
/// tồn thấp = còn hàng nhưng ≤ tồn tối thiểu; hết hàng = tồn ≤ 0;
/// lô sắp hết hạn = còn ≤ «số ngày cảnh báo» của từng hàng; lô hết hạn = HSD trước hôm nay (giờ VN).
/// </summary>
internal static class PosStockAlertHelper
{
    public static bool IsLowStock(decimal onHand, decimal minStock) =>
        minStock > 0 && onHand > 0 && onHand <= minStock;

    public sealed record ExpiryLot(Guid LotId, Guid ProductId, string ProductName, string? LotNo,
        DateTime ExpiryDate, decimal QtyOnHand, int DaysLeft, bool Expired);

    /// <summary>Lô còn tồn đã hết hạn hoặc trong ngưỡng cảnh báo (theo ExpiryWarningDays của hàng).</summary>
    public static async Task<List<ExpiryLot>> ExpiryLotsAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var today = PosStockLotHelper.ExpiryCutoffUtc();
        // Ngưỡng tối đa 365 ngày để giới hạn số dòng đọc; lọc chính xác theo từng hàng ở dưới.
        var horizon = today.AddDays(365);
        var rows = await db.PosStockLots.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
                        l.ExpiryDate != null && l.ExpiryDate <= horizon)
            .Select(l => new
            {
                l.Id, l.ProductId, l.LotNo, l.QtyOnHand, Expiry = l.ExpiryDate!.Value,
                Name = l.Product != null ? l.Product.Name : "",
                Warn = l.Product != null ? l.Product.ExpiryWarningDays : 30,
            })
            .ToListAsync(ct);
        return rows
            .Select(r => (r, days: (r.Expiry.Date - today.Date).Days))
            .Where(x => x.days < 0 || x.days <= Math.Max(1, x.r.Warn))
            .OrderBy(x => x.r.Expiry)
            .Select(x => new ExpiryLot(x.r.Id, x.r.ProductId, x.r.Name, x.r.LotNo, x.r.Expiry,
                x.r.QtyOnHand, x.days, x.days < 0))
            .ToList();
    }
}
