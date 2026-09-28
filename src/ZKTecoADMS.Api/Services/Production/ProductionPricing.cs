using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services.Production;

/// <summary>Khóa tính đơn giá lũy tiến: 1 nhân viên × 1 sản phẩm × 1 tháng.</summary>
public readonly record struct ProductionPriceKey(Guid EmployeeId, Guid ProductItemId, DateTime MonthStart)
{
    public static ProductionPriceKey Of(Guid employeeId, Guid productItemId, DateTime workDate) =>
        new(employeeId, productItemId, new DateTime(workDate.Year, workDate.Month, 1));
}

/// <summary>
/// Lương sản phẩm theo bậc lũy tiến trong THÁNG: tổng tiền tháng = tiền lũy tiến của tổng sản lượng tháng.
/// Mỗi lần thêm / sửa / xóa / import, cả tháng của (NV, SP) được tính lại theo thứ tự ngày —
/// trước đây mỗi dòng chỉ tính theo sản lượng đã có lúc nhập, nên sửa / xóa / nhập lùi ngày làm lệch tổng.
/// </summary>
public static class ProductionPricing
{
    /// <summary>Tiền lũy tiến cho [quantity] sản phẩm theo bậc (bậc 1 từ 1…Max, bậc sau nối tiếp; vượt bậc cuối dùng giá bậc cuối).</summary>
    public static decimal ProgressiveTotal(IReadOnlyList<ProductPriceTier> tiers, decimal quantity)
    {
        if (quantity <= 0 || tiers.Count == 0) return 0;
        decimal total = 0, counted = 0;
        var ordered = tiers.OrderBy(t => t.TierLevel).ToList();
        foreach (var tier in ordered)
        {
            if (counted >= quantity) break;
            var tierEnd = tier.MaxQuantity ?? quantity;
            var inTier = Math.Min(quantity, tierEnd) - counted;
            if (inTier <= 0) continue;
            total += inTier * tier.UnitPrice;
            counted += inTier;
        }
        if (counted < quantity)
            total += (quantity - counted) * ordered[^1].UnitPrice;
        return total;
    }

    /// <summary>
    /// Chia tiền lũy tiến cho từng dòng theo thứ tự: dòng i = Tổng(lũy kế đến i) − Tổng(lũy kế trước i).
    /// Tổng các dòng luôn = ProgressiveTotal(tổng sản lượng).
    /// </summary>
    public static List<(decimal UnitPrice, decimal Amount)> Allocate(
        IReadOnlyList<ProductPriceTier> tiers, IReadOnlyList<decimal> orderedQuantities)
    {
        var result = new List<(decimal, decimal)>(orderedQuantities.Count);
        decimal cumulative = 0;
        foreach (var qty in orderedQuantities)
        {
            var before = ProgressiveTotal(tiers, cumulative);
            cumulative += Math.Max(0, qty);
            var amount = ProgressiveTotal(tiers, cumulative) - before;
            var unit = qty > 0 ? Math.Round(amount / qty, 0) : 0;
            result.Add((unit, Math.Round(amount, 0)));
        }
        return result;
    }

    /// <summary>Tính lại đơn giá / thành tiền mọi dòng của các (NV, SP, tháng) bị ảnh hưởng.</summary>
    public static async Task RepriceAsync(ZKTecoDbContext db, Guid storeId, IEnumerable<ProductionPriceKey> keys)
    {
        var distinct = keys.Distinct().ToList();
        if (distinct.Count == 0) return;
        var productIds = distinct.Select(k => k.ProductItemId).Distinct().ToList();
        var tiersByProduct = (await db.ProductPriceTiers.AsNoTracking()
                .Where(t => productIds.Contains(t.ProductItemId) && t.Deleted == null)
                .ToListAsync())
            .GroupBy(t => t.ProductItemId)
            .ToDictionary(g => g.Key, g => (IReadOnlyList<ProductPriceTier>)g.OrderBy(t => t.TierLevel).ToList());

        foreach (var key in distinct)
        {
            var monthEnd = key.MonthStart.AddMonths(1);
            var entries = await db.ProductionEntries.AsTracking()
                .Where(e => e.StoreId == storeId && e.Deleted == null &&
                            e.EmployeeId == key.EmployeeId && e.ProductItemId == key.ProductItemId &&
                            e.WorkDate >= key.MonthStart && e.WorkDate < monthEnd)
                .OrderBy(e => e.WorkDate).ThenBy(e => e.CreatedAt).ThenBy(e => e.Id)
                .ToListAsync();
            if (entries.Count == 0) continue;
            var tiers = tiersByProduct.GetValueOrDefault(key.ProductItemId) ?? [];
            var priced = Allocate(tiers, entries.Select(e => e.Quantity).ToList());
            for (var i = 0; i < entries.Count; i++)
            {
                var (unit, amount) = priced[i];
                if (entries[i].UnitPrice == unit && entries[i].Amount == amount) continue;
                entries[i].UnitPrice = unit;
                entries[i].Amount = amount;
            }
        }
    }

    /// <summary>
    /// (NV, tháng) đã chốt lương (phiếu lương Đã duyệt / Đã trả) → khóa sổ sản lượng tháng đó.
    /// Trả về tập "EmployeeId|yyyy-MM".
    /// </summary>
    public static async Task<HashSet<string>> LockedEmployeeMonthsAsync(
        ZKTecoDbContext db, Guid storeId, IEnumerable<(Guid EmployeeId, DateTime WorkDate)> items)
    {
        var list = items.ToList();
        if (list.Count == 0) return [];
        var empIds = list.Select(x => x.EmployeeId).Distinct().ToList();
        var years = list.Select(x => x.WorkDate.Year).Distinct().ToList();
        var rows = await db.Payslips.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null &&
                        empIds.Contains(p.EmployeeId) && years.Contains(p.Year) &&
                        (p.Status == PayslipStatus.Approved || p.Status == PayslipStatus.Paid))
            .Select(p => new { p.EmployeeId, p.Year, p.Month })
            .ToListAsync();
        return rows.Select(r => LockKey(r.EmployeeId, r.Year, r.Month)).ToHashSet();
    }

    public static string LockKey(Guid employeeId, int year, int month) => $"{employeeId:N}|{year:D4}-{month:D2}";
    public static string LockKey(Guid employeeId, DateTime date) => LockKey(employeeId, date.Year, date.Month);
}
